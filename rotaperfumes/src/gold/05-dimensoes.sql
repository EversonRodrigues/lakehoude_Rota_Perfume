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
