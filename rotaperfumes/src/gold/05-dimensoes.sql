-- Gold · dimensoes conformadas
--
-- CONFORMADA quer dizer uma coisa concreta: a mesma dimensao serve todos os
-- marts, entao todos eles somam igual. O dia em que existirem duas dim_cliente,
-- duas diretorias vao levar numeros diferentes para a mesma reuniao.
--
-- A gold le SO da silver. Nunca da bronze: a bronze e texto sem contrato.

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_cliente
COMMENT 'Uma linha por cliente, ja deduplicado por CNPJ na silver. Traz o comportamento de compra agregado para nao obrigar todo mart a refazer o mesmo join.'
AS
WITH compras AS (
  SELECT
    p.cliente_id,
    min(p.data_pedido)        AS data_primeiro_pedido,
    max(p.data_pedido)        AS data_ultimo_pedido,
    count(*)                  AS total_pedidos,
    sum(p.valor_liquido)      AS receita_acumulada
  FROM lakehouse_rotaperfume.silver.pedidos p
  WHERE NOT p.cancelado
  GROUP BY p.cliente_id
)
SELECT
  c.cliente_id,
  c.cnpj,
  c.razao_social,
  c.segmento,
  c.cidade,
  c.uf,
  c.data_cadastro,
  c.ativo,
  co.data_primeiro_pedido,
  co.data_ultimo_pedido,
  coalesce(co.total_pedidos, 0)                              AS total_pedidos,
  coalesce(co.receita_acumulada, 0)                          AS receita_acumulada,
  datediff(current_date(), co.data_ultimo_pedido)            AS dias_sem_comprar,
  current_timestamp()                                        AS _processado_em
FROM lakehouse_rotaperfume.silver.clientes c
LEFT JOIN compras co ON co.cliente_id = c.cliente_id;

ALTER TABLE lakehouse_rotaperfume.gold.dim_cliente ALTER COLUMN dias_sem_comprar
  COMMENT 'Dias corridos desde a ultima compra nao cancelada. NULL quando o cliente nunca comprou -- nao e zero, e ausencia de compra.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_cliente ALTER COLUMN receita_acumulada
  COMMENT 'Soma historica de valor_liquido dos pedidos nao cancelados do cliente. Zero para quem nunca comprou.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_cliente ALTER COLUMN total_pedidos
  COMMENT 'Quantidade de pedidos nao cancelados. Pedido cancelado nao conta como relacionamento comercial.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_cliente ALTER COLUMN cliente_id
  COMMENT 'Chave do cliente, ja deduplicada por CNPJ na silver. Pedido antigo pode apontar para um id descartado -- o rastro fica em silver.clientes.cliente_ids_duplicados.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_cliente ALTER COLUMN segmento
  COMMENT 'Classificacao comercial do cliente (farmacia, perfumaria, magazine...). Vem do cadastro do CRM, nao e derivada do comportamento de compra.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_cliente ALTER COLUMN cidade
  COMMENT 'Cidade do cliente, como cadastrada no CRM. Analise regional confiavel usa `uf`: cidade tem grafia livre na origem.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_cliente ALTER COLUMN uf
  COMMENT 'Unidade federativa do cliente. E o corte geografico confiavel desta dimensao.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_cliente ALTER COLUMN ativo
  COMMENT 'Cadastro ativo no CRM. Booleano ja convertido do S/N que a bronze guarda como veio. Cliente inativo permanece na dimensao: a venda historica dele continua valendo.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_cliente ALTER COLUMN data_primeiro_pedido
  COMMENT 'Data do primeiro pedido nao cancelado. NULL para quem nunca comprou -- ausencia de compra, nao data zero.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_cliente ALTER COLUMN data_ultimo_pedido
  COMMENT 'Data do ultimo pedido nao cancelado. NUNCA use esta coluna como feature de ML: ela e agregada sobre a base inteira, sem data de corte, e vaza o futuro.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_cliente ALTER COLUMN _processado_em
  COMMENT 'Momento em que esta linha foi (re)gerada pelo pipeline. Metadado tecnico, nunca metrica de negocio.';

-- ---------------------------------------------------------------------------

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_produto
COMMENT 'Uma linha por SKU, com custo e preco de tabela para a margem ser calculada uma vez so, no fato.'
AS
SELECT
  p.sku,
  p.descricao,
  p.categoria,
  p.marca,
  p.nota_olfativa,
  p.unidade,
  p.custo_unitario,
  p.preco_tabela,
  p.data_lancamento,
  NOT p.ativo                                                AS descontinuado,
  current_timestamp()                                        AS _processado_em
FROM lakehouse_rotaperfume.silver.produtos p;

ALTER TABLE lakehouse_rotaperfume.gold.dim_produto ALTER COLUMN descontinuado
  COMMENT 'Produto saiu de linha. O item historico continua valendo -- descontinuado nao apaga venda passada.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_produto ALTER COLUMN sku
  COMMENT 'Codigo do produto, chave da dimensao. Formato SKU00000 -- e STRING, nunca numero.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_produto ALTER COLUMN descricao
  COMMENT 'Nome comercial do produto, o rotulo que aparece no relatorio e na sugestao de oferta ao vendedor.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_produto ALTER COLUMN categoria
  COMMENT 'Familia do produto (perfume, deo colonia, hidratante...). E o corte de analise mais amplo que marca.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_produto ALTER COLUMN marca
  COMMENT 'Marca do fabricante. Corte principal do ranking comercial e da analise de ruptura.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_produto ALTER COLUMN nota_olfativa
  COMMENT 'Familia olfativa (amadeirado, floral, citrico...). Atributo de afinidade: e por ela que se sugere um substituto quando o SKU preferido esta em falta.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_produto ALTER COLUMN unidade
  COMMENT 'Unidade de venda do SKU. Quantidade so e comparavel entre produtos de mesma unidade.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_produto ALTER COLUMN custo_unitario
  COMMENT 'Custo de aquisicao por unidade, em reais. Fica na dimensao para a margem ser calculada uma vez so, dentro do fato.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_produto ALTER COLUMN preco_tabela
  COMMENT 'Preco de tabela sugerido, em reais. E referencia, nao o praticado: o preco real da venda esta em fato_vendas.preco_praticado.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_produto ALTER COLUMN _processado_em
  COMMENT 'Momento em que esta linha foi (re)gerada pelo pipeline. Metadado tecnico, nunca metrica de negocio.';

-- ---------------------------------------------------------------------------

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_vendedor
COMMENT 'Uma linha por vendedor, com a meta mensal que o mart comercial usa para calcular atingimento.'
AS
SELECT
  v.vendedor_id,
  v.nome,
  v.regiao,
  v.uf,
  v.data_admissao,
  v.data_desligamento,
  v.meta_mensal,
  v.ativo,
  current_timestamp()                                        AS _processado_em
FROM lakehouse_rotaperfume.silver.vendedores v;

ALTER TABLE lakehouse_rotaperfume.gold.dim_vendedor ALTER COLUMN meta_mensal
  COMMENT 'Meta de receita por mes, em reais. Base do atingimento no mart comercial.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_vendedor ALTER COLUMN vendedor_id
  COMMENT 'Chave do vendedor, e a UNICA forma correta de identificar a pessoa: ha nomes repetidos nesta base (dois Henrique Oliveira, dois Vinicius Lopes). Agrupar por nome funde duas pessoas em silencio.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_vendedor ALTER COLUMN nome
  COMMENT 'Nome do vendedor, para EXIBIR. Nao e unico: use vendedor_id em qualquer agrupamento ou join.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_vendedor ALTER COLUMN regiao
  COMMENT 'Regiao comercial atribuida ao vendedor. Recorte de gestao, nao necessariamente igual a UF do cliente atendido.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_vendedor ALTER COLUMN uf
  COMMENT 'UF base do vendedor. Pode divergir da UF do cliente: carteira nao respeita fronteira estadual.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_vendedor ALTER COLUMN data_admissao
  COMMENT 'Entrada do vendedor na empresa. Delimita o periodo em que a receita dele e comparavel com a dos demais.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_vendedor ALTER COLUMN data_desligamento
  COMMENT 'Saida do vendedor. NULL para quem esta na ativa. Seis desligados ainda tem carteira vigente na origem -- por isso a fila semanal filtra elegibilidade ANTES do limite de 200.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_vendedor ALTER COLUMN ativo
  COMMENT 'Vendedor na ativa. Booleano ja convertido do S/N da bronze. Vendedor desligado permanece na dimensao: a venda historica dele continua valendo.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_vendedor ALTER COLUMN _processado_em
  COMMENT 'Momento em que esta linha foi (re)gerada pelo pipeline. Metadado tecnico, nunca metrica de negocio.';

-- ---------------------------------------------------------------------------

-- A espinha de datas sai do proprio dado (min e max de data_pedido), nao de
-- datas cravadas: se a base crescer, o calendario cresce junto.
CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_calendario
COMMENT 'Um dia por linha, cobrindo todo o periodo de pedidos. Existe para que "mes sem venda" apareca como zero no relatorio em vez de sumir da lista.'
AS
WITH limites AS (
  SELECT trunc(min(data_pedido), 'MM')                       AS inicio,
         last_day(max(data_pedido))                          AS fim
  FROM lakehouse_rotaperfume.silver.pedidos
),
dias AS (
  SELECT explode(sequence(inicio, fim, INTERVAL 1 DAY))      AS data
  FROM limites
)
SELECT
  data,
  year(data)                                                 AS ano,
  month(data)                                                AS mes,
  date_format(data, 'MMMM')                                  AS nome_mes,
  concat('T', quarter(data))                                 AS trimestre,
  dayofweek(data)                                            AS dia_semana_num,
  date_format(data, 'EEEE')                                  AS dia_semana,
  dayofweek(data) IN (1, 7)                                  AS fim_de_semana,
  month(data) IN (4, 6, 10)                                  AS mes_pico_setor,
  current_timestamp()                                        AS _processado_em
FROM dias;

ALTER TABLE lakehouse_rotaperfume.gold.dim_calendario ALTER COLUMN mes_pico_setor
  COMMENT 'Abril, junho e outubro: os tres meses de pico do setor de perfumaria (Dia das Maes, Namorados e a virada para o Natal). Regra de NEGOCIO, nao derivada do dado -- serve para comparar o realizado com o que era esperado.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_calendario ALTER COLUMN data
  COMMENT 'O dia, chave da dimensao. A espinha vai do primeiro ao ultimo mes com pedido na silver -- nao sao datas cravadas, o calendario cresce com a base.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_calendario ALTER COLUMN ano
  COMMENT 'Ano civil do dia. Corte anual de qualquer serie temporal.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_calendario ALTER COLUMN mes
  COMMENT 'Numero do mes, de 1 a 12. Lembre que a sazonalidade do setor e INVERTIDA: o pico de venda e o mes ANTERIOR a data comemorativa, porque o lojista compra antes.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_calendario ALTER COLUMN nome_mes
  COMMENT 'Nome do mes por extenso, para rotular eixo de grafico. Ordene sempre por `mes`, nunca por este texto.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_calendario ALTER COLUMN trimestre
  COMMENT 'Trimestre civil no formato T1 a T4. Recorte de fechamento da diretoria.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_calendario ALTER COLUMN dia_semana_num
  COMMENT 'Dia da semana como numero, 1 = domingo a 7 = sabado (convencao do dayofweek do Spark). Use para ORDENAR o dia da semana.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_calendario ALTER COLUMN dia_semana
  COMMENT 'Dia da semana por extenso, para EXIBIR. A ordenacao correta vem de dia_semana_num.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_calendario ALTER COLUMN fim_de_semana
  COMMENT 'Sabado ou domingo. Venda B2B se concentra em dia util: comparar semana com fim de semana sem este filtro distorce a media diaria.';
ALTER TABLE lakehouse_rotaperfume.gold.dim_calendario ALTER COLUMN _processado_em
  COMMENT 'Momento em que esta linha foi (re)gerada pelo pipeline. Metadado tecnico, nunca metrica de negocio.';
