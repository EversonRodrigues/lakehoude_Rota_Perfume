-- Silver · pedidos
--
-- 3.443 dos 28.729 pedidos tem a data em dd/MM/yyyy e o resto em ISO, no mesmo
-- campo. O coalesce de dois try_to_date nao deixa nenhuma data para tras -- e
-- try_to_date, nunca to_date: em ANSI mode o to_date ABORTA a query inteira ao
-- encontrar '15/10/2025', em vez de devolver nulo.
--
-- 957 pedidos estao cancelados e ja vieram com valor_total zerado, mas sem
-- nenhuma flag que diga isso. A coluna `cancelado` torna a regra explicita, e
-- `valor_liquido` passa a ser a coluna que a gold pode somar sem pensar.
--
-- CUIDADO com a constraint: a regra intuitiva seria valor_liquido >= 0, e ela
-- FALHA -- 135 pedidos tem valor negativo porque contem item devolvido. Isso e
-- negocio legitimo, nao sujeira. A regra certa e a que esta no fim do arquivo.

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.pedidos
COMMENT 'Pedidos tipados, com data normalizada a partir de dois formatos e o cancelamento explicito em coluna. valor_liquido e a coluna que a gold soma.'
AS
WITH tipado AS (
  SELECT
    CAST(pedido_id AS INT)                                   AS pedido_id,
    CAST(cliente_id AS INT)                                  AS cliente_id,
    CAST(vendedor_id AS INT)                                 AS vendedor_id,
    coalesce(try_to_date(data_pedido),
             try_to_date(data_pedido, 'dd/MM/yyyy'))         AS data_pedido,
    trim(canal)                                              AS canal,
    trim(status)                                             AS status,
    CAST(valor_total AS DECIMAL(18,2))                       AS valor_total,
    trim(status) = 'Cancelado'                               AS cancelado
  FROM lakehouse_rotaperfume.bronze.pedidos
)
SELECT
  pedido_id,
  cliente_id,
  vendedor_id,
  data_pedido,
  year(data_pedido)                                          AS ano,
  month(data_pedido)                                         AS mes,
  canal,
  status,
  cancelado,
  valor_total,
  CASE WHEN cancelado THEN CAST(0 AS DECIMAL(18,2)) ELSE valor_total END AS valor_liquido,
  current_timestamp()                                        AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.pedidos) AS _linhas_origem
FROM tipado;

ALTER TABLE lakehouse_rotaperfume.silver.pedidos ALTER COLUMN data_pedido
  COMMENT 'coalesce de dois try_to_date: 3.443 pedidos vieram em dd/MM/yyyy e o resto em ISO, no mesmo campo.';
ALTER TABLE lakehouse_rotaperfume.silver.pedidos ALTER COLUMN cancelado
  COMMENT 'Derivada de status = Cancelado. Na origem o cancelamento so aparecia como valor_total zerado, sem flag.';
ALTER TABLE lakehouse_rotaperfume.silver.pedidos ALTER COLUMN valor_liquido
  COMMENT 'Zero quando cancelado, senao valor_total. Pode ser NEGATIVO: 135 pedidos contem item devolvido, e isso e negocio legitimo.';

-- O contrato.
ALTER TABLE lakehouse_rotaperfume.silver.pedidos
  ADD CONSTRAINT data_pedido_obrigatoria CHECK (data_pedido IS NOT NULL);
-- Nao use valor_liquido >= 0 aqui: falha nos 135 pedidos com devolucao.
ALTER TABLE lakehouse_rotaperfume.silver.pedidos
  ADD CONSTRAINT pedido_cancelado_zerado CHECK (NOT cancelado OR valor_liquido = 0);
