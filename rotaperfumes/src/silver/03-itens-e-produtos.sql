-- Silver · produtos e itens_pedido
--
-- A DECISAO DA NOITE mora aqui. 2.327 itens tem quantidade negativa. Isso nao e
-- erro de digitacao: e devolucao. Ha tres caminhos, e cada um da um numero
-- diferente para o diretor:
--
--   1. descartar as linhas negativas  -> o faturamento INFLA em mais de um milhao
--   2. manter sem flag                -> toda soma da empresa fica poluida
--   3. manter COM flag                -> preserva os dois numeros  <-- este
--
-- Por isso nenhuma linha e descartada: `devolucao` sinaliza e `quantidade_abs`
-- da o modulo, e quem faz a analise decide se quer o bruto ou o liquido.

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.produtos
COMMENT 'Catalogo de produtos tipado. ativo vira boolean e data_lancamento passa por try_to_date -- parte dos produtos nao tem data de lancamento na origem.'
AS
SELECT
  trim(sku)                                                     AS sku,
  trim(regexp_replace(descricao, '\\s+', ' '))                  AS descricao,
  trim(categoria)                                               AS categoria,
  trim(marca)                                                   AS marca,
  trim(nota_olfativa)                                           AS nota_olfativa,
  CAST(preco_tabela AS DECIMAL(18,2))                           AS preco_tabela,
  CAST(custo_unitario AS DECIMAL(18,2))                         AS custo_unitario,
  trim(unidade)                                                 AS unidade,
  upper(trim(ativo)) = 'S'                                      AS ativo,
  coalesce(try_to_date(data_lancamento),
           try_to_date(data_lancamento, 'dd/MM/yyyy'))          AS data_lancamento,
  current_timestamp()                                           AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.produtos)  AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.produtos;

ALTER TABLE lakehouse_rotaperfume.silver.produtos ALTER COLUMN data_lancamento
  COMMENT 'try_to_date: parte dos produtos vem sem data de lancamento, e fica NULL em vez de abortar a carga.';

ALTER TABLE lakehouse_rotaperfume.silver.produtos
  ADD CONSTRAINT sku_obrigatorio CHECK (sku IS NOT NULL AND length(sku) > 0);

-- ---------------------------------------------------------------------------

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.itens_pedido
COMMENT 'Itens tipados. Quantidade negativa e DEVOLUCAO e permanece na tabela, sinalizada em devolucao -- descartar essas linhas inflaria o faturamento em mais de um milhao.'
AS
WITH tipado AS (
  SELECT
    CAST(i.item_id AS INT)                     AS item_id,
    CAST(i.pedido_id AS INT)                   AS pedido_id,
    trim(i.sku)                                AS sku,
    CAST(i.quantidade AS INT)                  AS quantidade,
    CAST(i.preco_praticado AS DECIMAL(18,2))   AS preco_praticado,
    CAST(i.desconto_pct AS DECIMAL(9,4))       AS desconto_pct,
    CAST(i.valor_bruto AS DECIMAL(18,2))       AS valor_bruto
  FROM lakehouse_rotaperfume.bronze.itens_pedido i
)
SELECT
  t.item_id,
  t.pedido_id,
  t.sku,
  t.quantidade,
  t.quantidade < 0                                                  AS devolucao,
  abs(t.quantidade)                                                 AS quantidade_abs,
  t.preco_praticado,
  t.desconto_pct,
  t.valor_bruto,
  -- O produto saiu de linha, mas o item historico continua valendo.
  coalesce(NOT p.ativo, false)                                      AS sku_descontinuado,
  current_timestamp()                                               AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.itens_pedido)  AS _linhas_origem
FROM tipado t
LEFT JOIN lakehouse_rotaperfume.silver.produtos p ON p.sku = t.sku;

ALTER TABLE lakehouse_rotaperfume.silver.itens_pedido ALTER COLUMN devolucao
  COMMENT 'true quando a quantidade veio negativa na origem. Sao 2.327 itens, e eles NAO sao descartados: descartar inflaria o faturamento.';
ALTER TABLE lakehouse_rotaperfume.silver.itens_pedido ALTER COLUMN quantidade_abs
  COMMENT 'Modulo da quantidade, para contar peca movimentada sem que a devolucao subtraia do volume.';
ALTER TABLE lakehouse_rotaperfume.silver.itens_pedido ALTER COLUMN sku_descontinuado
  COMMENT 'true quando o produto do item nao esta mais ativo. Expoe o problema em vez de esconder: sao 76 itens.';

-- O contrato. quantidade_abs > 0 vale porque nenhum item tem quantidade zero.
ALTER TABLE lakehouse_rotaperfume.silver.itens_pedido
  ADD CONSTRAINT quantidade_abs_positiva CHECK (quantidade_abs > 0);
