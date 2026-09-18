-- O desfecho da semana, por vendedor: quanto da fila foi trabalhado, no que
-- deu, e quanto disso virou dinheiro.
--
-- Escrita na entrega anterior e ampliada aqui com as tres colunas de valor, que
-- sao o que o diretor pergunta depois de olhar a contagem.
--
-- No comeco da semana `trabalhados` e zero para todo mundo, e a tela precisa
-- dizer isso em vez de parecer quebrada.
--
-- Chave por vendedor_id; o nome e so rotulo -- dois vendedores desta base tem
-- nome repetido (36 por id contra 35 por nome).
--
-- ATENCAO ao significado das tres colunas de R$: sao ESTIMATIVA. `ticket_medio`
-- e a media historica do cliente, nao o valor do pedido que acabou de fechar --
-- esse a gente so conhece quando o pedido entra no ERP e desce pelo pipeline.
-- A tela rotula como estimativa; nao troque o rotulo sem trocar a conta.
WITH ultimo_retorno AS (
  SELECT cliente_id, status, registrado_em
  FROM   lakehouse_rotaperfume.gold.retorno_ligacao
  QUALIFY ROW_NUMBER() OVER (PARTITION BY cliente_id ORDER BY registrado_em DESC) = 1
)
SELECT
  f.vendedor_id,
  f.vendedor,
  COUNT(*)                                         AS na_fila,
  COUNT(r.cliente_id)                              AS trabalhados,
  COUNT_IF(r.status = 'vendeu')                    AS vendeu,
  COUNT_IF(r.status = 'vai_pensar')                AS vai_pensar,
  COUNT_IF(r.status = 'sem_interesse')             AS sem_interesse,
  COUNT_IF(r.status = 'nao_atendeu')               AS nao_atendeu,
  -- COALESCE porque SUM sobre zero linhas devolve NULL, e a tela mostraria
  -- travessao onde o numero certo e zero.
  ROUND(COALESCE(SUM(CASE WHEN r.status = 'vendeu'     THEN f.ticket_medio END), 0), 2) AS receita_fechada,
  ROUND(COALESCE(SUM(CASE WHEN r.status = 'vai_pensar' THEN f.ticket_medio END), 0), 2) AS receita_aberta,
  ROUND(COALESCE(SUM(f.score * f.ticket_medio), 0), 2)                                  AS receita_esperada,
  -- Frescor: de quando e o retorno mais novo deste vendedor. NULL enquanto ele
  -- nao registrou nada, e a tela le o maior de todos para datar o cabecalho.
  MAX(r.registrado_em)                             AS ultimo_retorno_em
FROM   lakehouse_rotaperfume.gold.fila_semanal f
LEFT   JOIN ultimo_retorno r ON r.cliente_id = f.cliente_id
GROUP  BY f.vendedor_id, f.vendedor
ORDER  BY trabalhados DESC, na_fila DESC
