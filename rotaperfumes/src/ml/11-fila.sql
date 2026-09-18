-- =========================================================================
-- A FILA E AS FERRAMENTAS
--
-- Score nao e decisao. `0,8412` nao e uma acao. Este arquivo e o ultimo metro:
-- o que separa o modelo que roda do modelo que alguem usa.
--
-- A ORDEM DAS OPERACOES E O PONTO DA NOITE, e o erro mais facil de cometer:
--   1o  juntar a carteira e DESCARTAR quem nao e elegivel
--   2o  so entao ORDER BY score DESC LIMIT 200
--   3o  ROW_NUMBER() por vendedor para dar a ordem de ligacao
--
-- Se o descarte vier DEPOIS do LIMIT, a fila fecha em 165 linhas em vez de 200
-- -- seis dos 42 vendedores estao desligados e levam junto os clientes deles --
-- e o teste 1 quebra o job. Medido neste workspace.
--
-- A fila e GLOBAL; a capacidade e que e por pessoa. Nada de cota igual por
-- vendedor: se a carteira do Joao esta quente e a do Pedro esta fria, cota fixa
-- obriga o Joao a deixar cliente quente na mesa.
-- =========================================================================

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.fila_semanal
COMMENT 'As 200 ligacoes da semana, uma por linha, ja atribuidas ao vendedor dono da carteira. Fila global ordenada por score: a capacidade e que e por pessoa, nao a cota. Cliente sem carteira vigente ou de vendedor desligado nao entra.'
AS
WITH
-- 1o passo: elegiveis. O descarte vem ANTES do limite, sempre.
elegivel AS (
  SELECT
    c.vendedor_id,
    v.nome                                   AS vendedor,
    s.cliente_id,
    s.score,
    s.faixa,
    s.vezes_base,
    d.razao_social,
    d.cidade,
    d.uf,
    f.ticket_medio,
    f.valor_total,
    f.recencia_dias,
    f.intervalo_medio_dias,
    f.atraso_relativo,
    f.comprou_lancamento
  FROM lakehouse_rotaperfume.gold.score_propensao s
  JOIN lakehouse_rotaperfume.silver.carteira c
    ON c.cliente_id = s.cliente_id
   -- As duas condicoes, de proposito: `vigente` ja exclui desligado na silver de
   -- hoje, mas escrever as duas documenta a intencao e sobrevive a uma mudanca
   -- na definicao da silver.
   AND c.vigente
   AND NOT c.orfao_vendedor_desligado
  JOIN lakehouse_rotaperfume.silver.vendedores v ON v.vendedor_id = c.vendedor_id
  JOIN lakehouse_rotaperfume.gold.dim_cliente d  ON d.cliente_id = s.cliente_id
  JOIN lakehouse_rotaperfume.gold.features_cliente f ON f.cliente_id = s.cliente_id
),
-- 2o passo: os 200 melhores da base inteira.
duzentos AS (
  SELECT * FROM elegivel ORDER BY score DESC LIMIT 200
),
-- O saldo vem do ultimo snapshot DE CADA SKU, nao do ultimo snapshot da tabela:
-- o snapshot global mais recente cobre 80 SKUs, o por-SKU cobre os 292.
estoque_atual AS (
  SELECT e.sku, e.saldo, e.ruptura
  FROM lakehouse_rotaperfume.silver.estoque e
  JOIN (SELECT sku, MAX(data_snapshot) AS d FROM lakehouse_rotaperfume.silver.estoque GROUP BY sku) u
    ON u.sku = e.sku AND u.d = e.data_snapshot
),
-- A marca preferida do cliente, por receita acumulada.
marca_preferida AS (
  SELECT cliente_id, marca FROM (
    SELECT cliente_id, marca, SUM(receita) AS r,
           ROW_NUMBER() OVER (PARTITION BY cliente_id ORDER BY SUM(receita) DESC, marca) AS pos
    FROM lakehouse_rotaperfume.gold.fato_vendas
    GROUP BY cliente_id, marca
  ) WHERE pos = 1
),
-- O SKU mais comprado na marca preferida que ele NAO comprou nos ultimos 90
-- dias. E a diferenca entre "sugestao" e "lista de produtos".
sugestao AS (
  SELECT cliente_id, sku, saldo, disponivel FROM (
    SELECT fv.cliente_id, fv.sku, ea.saldo,
           COALESCE(ea.saldo, 0) > 0 AND NOT COALESCE(ea.ruptura, FALSE) AS disponivel,
           -- DISPONIBILIDADE PRIMEIRO, volume depois. Este ORDER BY ja ordenou
           -- so por SUM(quantidade), e era um bug de negocio com cara de detalhe
           -- tecnico: o SKU mais comprado vencia mesmo com saldo zero, o saldo
           -- so era olhado DEPOIS, no CASE la embaixo, e a fila saia mandando
           -- oferecer o que o estoque nao tem. Filtro de disponibilidade em
           -- WHERE seria pior: deixaria o cliente sem nenhuma sugestao em vez de
           -- mostrar a segunda melhor opcao que existe no deposito.
           ROW_NUMBER() OVER (
             PARTITION BY fv.cliente_id
             ORDER BY (COALESCE(ea.saldo, 0) > 0 AND NOT COALESCE(ea.ruptura, FALSE)) DESC,
                      SUM(fv.quantidade) DESC,
                      fv.sku) AS pos
    FROM lakehouse_rotaperfume.gold.fato_vendas fv
    JOIN marca_preferida mp ON mp.cliente_id = fv.cliente_id AND mp.marca = fv.marca
    LEFT JOIN estoque_atual ea ON ea.sku = fv.sku
    WHERE NOT EXISTS (
      SELECT 1 FROM lakehouse_rotaperfume.gold.fato_vendas r
      WHERE r.cliente_id = fv.cliente_id AND r.sku = fv.sku
        AND r.data_pedido >= DATE'2026-08-31' - INTERVAL 90 DAYS
    )
    GROUP BY fv.cliente_id, fv.sku, ea.saldo, ea.ruptura
  ) WHERE pos = 1
)
SELECT
  q.vendedor_id,
  q.vendedor,
  -- 3o passo: a ordem de ligacao dentro da carteira de cada um.
  --
  -- PARTITION BY vendedor_id, nunca pelo NOME: existem dois "Henrique Oliveira"
  -- (ids 34 e 36) e dois "Vinicius Lopes" (31 e 37) na base. Particionar pelo
  -- nome funde as carteiras de duas pessoas diferentes numa fila so, e nenhuma
  -- das duas sabe quais ligacoes sao suas.
  CAST(ROW_NUMBER() OVER (PARTITION BY q.vendedor_id ORDER BY q.score DESC) AS INT) AS ordem,
  CAST(q.cliente_id AS INT)                  AS cliente_id,
  q.razao_social,
  q.cidade,
  q.uf,
  q.score,
  q.faixa,
  -- A faixa nunca viaja sozinha: 0,45 so quer dizer alguma coisa ao lado de
  -- "4,4x a chance media da base".
  q.vezes_base,
  q.ticket_medio,
  -- O motivo em portugues nao e enfeite: e o que faz o vendedor confiar quando
  -- o modelo acerta, e entender POR QUE quando ele erra -- em vez de
  -- simplesmente parar de usar. O ELSE e obrigatorio: motivo nulo quebra o
  -- teste 2.
  -- A ORDEM DOS WHEN define o que o vendedor le. `comprou_lancamento` e
  -- verdadeiro em 71% da base, entao coloca-lo cedo faz 85% da fila receber a
  -- MESMA frase -- e motivo que se repete em 170 de 200 linhas nao explica
  -- nada. Ele desce para depois dos sinais especificos.
  --
  -- A faixa de 1,0 a 1,5 e a mais acionavel de todas e nao estava prevista:
  -- nela a taxa de compra medida e de 36,6%, contra 10,12% da base.
  CASE
    WHEN q.atraso_relativo > 3 THEN concat(
      'Compra a cada ', format_number(q.intervalo_medio_dias, 0),
      ' dias e esta ha ', format_number(q.recencia_dias, 0),
      ' sem pedido. Risco de perder para o concorrente.')
    WHEN q.atraso_relativo > 1.5 THEN concat(
      'Esta ', format_number(q.atraso_relativo, 1),
      ' vezes mais atrasado que o ritmo dele.')
    WHEN q.atraso_relativo >= 1.0 THEN concat(
      'No ponto do ciclo: compra a cada ', format_number(q.intervalo_medio_dias, 0),
      ' dias e esta ha ', format_number(q.recencia_dias, 0),
      '. E a faixa que mais compra.')
    WHEN q.valor_total >= (SELECT percentile(valor_total, 0.9) FROM duzentos) THEN concat(
      'Cliente grande, R$ ', format_number(q.valor_total, 2), ' no ano. Manter proximo.')
    WHEN q.comprou_lancamento = 1 THEN
      'Comprou lancamento recente. Alta chance de repetir.'
    ELSE 'Dentro do ritmo. Contato de manutencao.'
  END                                        AS motivo,
  -- A palavra 'Oferecer' so aparece quando ha saldo. Quando nao ha, o texto nao
  -- manda oferecer coisa nenhuma: diz que nao ha o que oferecer da marca
  -- preferida. Um aviso no fim da frase nao segura ninguem -- o vendedor le o
  -- verbo, liga e promete.
  CASE
    WHEN sg.sku IS NULL THEN 'Sem sugestao: ja comprou tudo da marca preferida nos ultimos 90 dias.'
    WHEN sg.disponivel THEN concat('Oferecer ', sg.sku, ' (', CAST(sg.saldo AS STRING), ' em estoque).')
    WHEN sg.saldo IS NULL THEN concat('Sem sugestao com estoque confirmado. O mais proximo e ', sg.sku, ', sem snapshot recente -- confira antes de prometer.')
    ELSE concat('Sem sugestao com estoque: nada da marca preferida tem saldo hoje. O mais proximo e ', sg.sku, ', zerado ou em ruptura.')
  END                                        AS sugestao,
  current_timestamp()                        AS _gerada_em
FROM duzentos q
LEFT JOIN sugestao sg ON sg.cliente_id = q.cliente_id;

ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN vendedor_id
  COMMENT 'Id do vendedor dono da carteira. E a chave de verdade: ha nomes repetidos na base (dois Henrique Oliveira, dois Vinicius Lopes), entao agrupar por nome funde carteiras de pessoas diferentes.';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN vendedor
  COMMENT 'Nome do vendedor, para leitura. Nao e unico -- use vendedor_id para agrupar. Seis dos 42 vendedores estao desligados e nao aparecem aqui.';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN ordem
  COMMENT 'Ordem de ligacao DENTRO da carteira do vendedor, do maior score para o menor.';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN motivo
  COMMENT 'Frase em portugues explicando por que o cliente esta na fila, com os numeros reais dele. Nunca nula.';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN sugestao
  COMMENT 'O que oferecer: o SKU mais comprado na marca preferida que o cliente nao leva ha 90 dias, com o saldo do ultimo snapshot daquele SKU.';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN vezes_base
  COMMENT 'Quantas vezes a chance deste cliente supera a taxa base (a conversao de quem liga sem modelo). E o denominador da faixa: sem ele, um score de 0,45 parece pouco.';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN score
  COMMENT 'Probabilidade de compra nos proximos 7 dias, vinda de gold.score_propensao.';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN cliente_id
  COMMENT 'Cliente a ligar. E a chave que liga esta fila a gold.retorno_ligacao, onde o time registra o que aconteceu depois.';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN cidade
  COMMENT 'Cidade do cliente, para o vendedor se situar antes de ligar. Grafia livre na origem -- para agrupar, use uf.';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN uf
  COMMENT 'UF do cliente. E o corte geografico confiavel da fila.';
ALTER TABLE lakehouse_rotaperfume.gold.fila_semanal ALTER COLUMN _gerada_em
  COMMENT 'Momento em que a fila foi montada. Identifica a SEMANA da fila e casa com gold.retorno_ligacao._referencia. Metadado tecnico, nunca metrica de negocio.';

-- =========================================================================
-- AS QUATRO FERRAMENTAS
--
-- Agente nao inventa: ele consulta. Sao quatro consultas ao Unity Catalog, com
-- nome e contrato. O COMMENT nao e documentacao -- e o que o agente LE para
-- decidir qual chamar.
--
-- Todo parametro com prefixo p_: parametro homonimo de coluna fica ambiguo
-- dentro do corpo e o CREATE falha.
-- =========================================================================

CREATE OR REPLACE FUNCTION lakehouse_rotaperfume.gold.priorizar_carteira(
  p_vendedor STRING COMMENT 'Nome do vendedor, como aparece em gold.fila_semanal',
  p_quantos INT COMMENT 'Quantas ligacoes devolver, da mais prioritaria para a menos'
)
RETURNS TABLE (vendedor_id INT, ordem INT, cliente_id INT, razao_social STRING,
               cidade STRING, score DOUBLE, motivo STRING, sugestao STRING)
COMMENT 'Devolve a fila de ligacoes da semana de um vendedor, ja priorizada. Use quando perguntarem para quem ligar, quem contatar primeiro ou qual e a lista da semana.'
RETURN
  -- Nada de `LIMIT p_quantos`: a expressao do LIMIT tem que ser CONSTANTE, e
  -- parametro de funcao nao e (INVALID_LIMIT_LIKE_EXPRESSION.IS_UNFOLDABLE).
  -- Como `ordem` ja e o ranking dentro da carteira, o filtro faz o mesmo.
  SELECT vendedor_id, ordem, cliente_id, razao_social, cidade, score, motivo, sugestao
  FROM lakehouse_rotaperfume.gold.fila_semanal
  WHERE vendedor = p_vendedor
    AND ordem <= p_quantos
  ORDER BY vendedor_id, ordem;

CREATE OR REPLACE FUNCTION lakehouse_rotaperfume.gold.contexto_cliente(
  p_cliente_id INT COMMENT 'Identificador do cliente em gold.dim_cliente'
)
RETURNS TABLE (razao_social STRING, cidade STRING, segmento STRING,
               pedidos BIGINT, receita_total DECIMAL(18,2), ticket_medio DECIMAL(18,2),
               ultima_compra DATE, marca_preferida STRING)
COMMENT 'Historico comercial de um cliente: quanto comprou, com que frequencia, ticket medio, ultima compra e marca preferida. Use antes de ligar, para saber com quem se esta falando.'
RETURN
  SELECT
    MAX(d.razao_social), MAX(d.cidade), MAX(d.segmento),
    COUNT(DISTINCT f.pedido_id), CAST(SUM(f.receita) AS DECIMAL(18,2)),
    CAST(SUM(f.receita) / NULLIF(COUNT(DISTINCT f.pedido_id), 0) AS DECIMAL(18,2)),
    MAX(f.data_pedido),
    MAX_BY(f.marca, f.receita)
  FROM lakehouse_rotaperfume.gold.fato_vendas f
  JOIN lakehouse_rotaperfume.gold.dim_cliente d ON d.cliente_id = f.cliente_id
  WHERE f.cliente_id = p_cliente_id;

CREATE OR REPLACE FUNCTION lakehouse_rotaperfume.gold.sugerir_produtos(
  p_cliente_id INT COMMENT 'Identificador do cliente em gold.dim_cliente'
)
RETURNS TABLE (sku STRING, descricao STRING, marca STRING,
               vezes_comprado BIGINT, ultima_compra DATE, dias_sem_comprar INT)
COMMENT 'Produtos que o cliente ja comprou e parou de comprar nos ultimos 90 dias, do mais frequente para o menos. Use para sugerir o que oferecer na ligacao.'
RETURN
  SELECT f.sku, MAX(p.descricao), MAX(f.marca),
         COUNT(DISTINCT f.pedido_id), MAX(f.data_pedido),
         CAST(DATEDIFF(DATE'2026-08-31', MAX(f.data_pedido)) AS INT)
  FROM lakehouse_rotaperfume.gold.fato_vendas f
  JOIN lakehouse_rotaperfume.gold.dim_produto p ON p.sku = f.sku
  WHERE f.cliente_id = p_cliente_id
  GROUP BY f.sku
  HAVING MAX(f.data_pedido) < DATE'2026-08-31' - INTERVAL 90 DAYS
  ORDER BY COUNT(DISTINCT f.pedido_id) DESC;

CREATE OR REPLACE FUNCTION lakehouse_rotaperfume.gold.checar_disponibilidade(
  p_sku STRING COMMENT 'Codigo do produto, como SKU00042'
)
RETURNS TABLE (sku STRING, descricao STRING, saldo INT, ruptura BOOLEAN, data_snapshot DATE)
COMMENT 'Saldo de estoque de um SKU no snapshot mais recente daquele produto. Use antes de prometer entrega: nunca afirme disponibilidade sem consultar aqui.'
RETURN
  SELECT e.sku, MAX(p.descricao), MAX(e.saldo), MAX(e.ruptura), MAX(e.data_snapshot)
  FROM lakehouse_rotaperfume.silver.estoque e
  LEFT JOIN lakehouse_rotaperfume.gold.dim_produto p ON p.sku = e.sku
  WHERE e.sku = p_sku
    AND e.data_snapshot = (SELECT MAX(data_snapshot) FROM lakehouse_rotaperfume.silver.estoque x WHERE x.sku = p_sku)
  GROUP BY e.sku;

-- =========================================================================
-- OS QUATRO TESTES QUE QUEBRAM O JOB
-- =========================================================================

SELECT 'teste 1 · a fila tem exatamente 200 linhas'                  AS teste,
       linhas AS calculado, 200 AS esperado,
       CASE WHEN linhas = 200 THEN 'PASSOU'
            ELSE raise_error(concat('a fila saiu com ', linhas,
                 ' linhas. Quase sempre e o descarte de vendedor desligado rodando DEPOIS do LIMIT 200.')) END AS resultado
FROM (SELECT COUNT(*) AS linhas FROM lakehouse_rotaperfume.gold.fila_semanal);

SELECT 'teste 2 · nenhum motivo nulo ou vazio'                       AS teste,
       sem_motivo AS calculado, 0 AS esperado,
       CASE WHEN sem_motivo = 0 THEN 'PASSOU'
            ELSE raise_error(concat(sem_motivo, ' linhas sem motivo -- faltou o ELSE no CASE WHEN')) END AS resultado
FROM (SELECT COUNT(*) AS sem_motivo FROM lakehouse_rotaperfume.gold.fila_semanal
      WHERE motivo IS NULL OR length(trim(motivo)) = 0);

SELECT 'teste 3 · score dentro de [0,1]'                             AS teste,
       fora AS calculado, 0 AS esperado,
       CASE WHEN fora = 0 THEN 'PASSOU'
            ELSE raise_error(concat(fora, ' linhas com score fora do intervalo [0,1]')) END AS resultado
FROM (SELECT COUNT(*) AS fora FROM lakehouse_rotaperfume.gold.fila_semanal
      WHERE score < 0 OR score > 1);

-- O teste que prende a correcao da sugestao. Enquanto o ROW_NUMBER ordenava so
-- por volume, esta contagem era diferente de zero: a fila mandava oferecer SKU
-- sem saldo. Nunca relaxe este teste para o job ficar verde -- a sugestao com
-- estoque zerado nao e um alarme falso, e uma promessa que o deposito nao paga.
SELECT 'teste 4 · nenhuma sugestao manda oferecer SKU sem saldo'     AS teste,
       oferece_sem_saldo AS calculado, 0 AS esperado,
       CASE WHEN oferece_sem_saldo = 0 THEN 'PASSOU'
            ELSE raise_error(concat(oferece_sem_saldo,
                 ' linhas mandam oferecer um SKU sem estoque. A disponibilidade tem que entrar no ORDER BY do ROW_NUMBER, nao so no CASE do texto.')) END AS resultado
FROM (
  SELECT COUNT(*) AS oferece_sem_saldo
  FROM lakehouse_rotaperfume.gold.fila_semanal f
  JOIN (
    SELECT e.sku, e.saldo, e.ruptura
    FROM lakehouse_rotaperfume.silver.estoque e
    JOIN (SELECT sku, MAX(data_snapshot) AS d FROM lakehouse_rotaperfume.silver.estoque GROUP BY sku) u
      ON u.sku = e.sku AND u.d = e.data_snapshot
  ) ea ON f.sugestao LIKE concat('Oferecer ', ea.sku, '%')
  WHERE ea.saldo <= 0 OR ea.ruptura
);
