-- Silver · CRM e financeiro
--
-- vendedores, carteira, oportunidades, visitas, pagamentos e estoque.
--
-- O caso interessante e a CARTEIRA: existem 441 carteiras sem data_fim cujo
-- vendedor ja foi desligado. Nao consertamos o dado -- consertar aqui seria
-- decidir, sozinhos, o que fazer com a carteira de seis vendedores que sairam.
-- Em vez disso, `vigente` diz o que de fato esta valendo e
-- `orfao_vendedor_desligado` EXPOE o problema para o gestor resolver.

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.vendedores
COMMENT 'Vendedores tipados. data_desligamento nula significa vendedor ativo -- e a coluna que a carteira consulta para detectar orfandade.'
AS
SELECT
  CAST(vendedor_id AS INT)                                       AS vendedor_id,
  initcap(trim(regexp_replace(nome, '\\s+', ' ')))               AS nome,
  trim(regiao)                                                   AS regiao,
  upper(trim(uf))                                                AS uf,
  coalesce(try_to_date(data_admissao),
           try_to_date(data_admissao, 'dd/MM/yyyy'))             AS data_admissao,
  coalesce(try_to_date(data_desligamento),
           try_to_date(data_desligamento, 'dd/MM/yyyy'))         AS data_desligamento,
  CAST(meta_mensal AS DECIMAL(18,2))                             AS meta_mensal,
  coalesce(try_to_date(data_desligamento),
           try_to_date(data_desligamento, 'dd/MM/yyyy')) IS NULL AS ativo,
  current_timestamp()                                            AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.vendedores)  AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.vendedores;

-- ---------------------------------------------------------------------------

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.carteira
COMMENT 'Carteira cliente-vendedor. Nao corrige a orfandade: expoe em orfao_vendedor_desligado as 441 carteiras abertas cujo vendedor ja saiu da empresa.'
AS
WITH tipado AS (
  SELECT
    CAST(carteira_id AS INT)                              AS carteira_id,
    CAST(cliente_id AS INT)                               AS cliente_id,
    CAST(vendedor_id AS INT)                              AS vendedor_id,
    coalesce(try_to_date(data_inicio),
             try_to_date(data_inicio, 'dd/MM/yyyy'))      AS data_inicio,
    coalesce(try_to_date(data_fim),
             try_to_date(data_fim, 'dd/MM/yyyy'))         AS data_fim
  FROM lakehouse_rotaperfume.bronze.carteira
)
SELECT
  c.carteira_id,
  c.cliente_id,
  c.vendedor_id,
  c.data_inicio,
  c.data_fim,
  -- Vigente de verdade: a carteira esta aberta E o vendedor ainda esta na casa.
  c.data_fim IS NULL AND v.data_desligamento IS NULL              AS vigente,
  -- O problema, exposto em vez de escondido.
  c.data_fim IS NULL AND v.data_desligamento IS NOT NULL          AS orfao_vendedor_desligado,
  current_timestamp()                                             AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.carteira)    AS _linhas_origem
FROM tipado c
LEFT JOIN lakehouse_rotaperfume.silver.vendedores v ON v.vendedor_id = c.vendedor_id;

ALTER TABLE lakehouse_rotaperfume.silver.carteira ALTER COLUMN vigente
  COMMENT 'Carteira aberta (data_fim nula) E vendedor nao desligado. As duas condicoes: so data_fim nao basta.';
ALTER TABLE lakehouse_rotaperfume.silver.carteira ALTER COLUMN orfao_vendedor_desligado
  COMMENT 'Carteira aberta cujo vendedor ja foi desligado: 441 casos. O dado nao foi corrigido de proposito -- a decisao e do gestor comercial.';

-- ---------------------------------------------------------------------------

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.oportunidades
COMMENT 'Funil de oportunidades. As etapas de fechamento na origem sao "Fechado ganho" e "Fechado perdido" -- nao "Ganha"/"Perdida".'
AS
SELECT
  CAST(oportunidade_id AS INT)                                       AS oportunidade_id,
  CAST(cliente_id AS INT)                                            AS cliente_id,
  CAST(vendedor_id AS INT)                                           AS vendedor_id,
  trim(origem)                                                       AS origem,
  trim(etapa)                                                        AS etapa,
  trim(etapa) = 'Fechado ganho'                                      AS ganha,
  trim(etapa) = 'Fechado perdido'                                    AS perdida,
  trim(etapa) IN ('Fechado ganho', 'Fechado perdido')                AS fechada,
  CAST(probabilidade_pct AS INT)                                     AS probabilidade_pct,
  CAST(valor_estimado AS DECIMAL(18,2))                              AS valor_estimado,
  coalesce(try_to_date(data_abertura),
           try_to_date(data_abertura, 'dd/MM/yyyy'))                 AS data_abertura,
  coalesce(try_to_date(data_fechamento),
           try_to_date(data_fechamento, 'dd/MM/yyyy'))               AS data_fechamento,
  CAST(ciclo_dias AS INT)                                            AS ciclo_dias,
  nullif(trim(motivo_perda), '')                                     AS motivo_perda,
  current_timestamp()                                                AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.oportunidades)   AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.oportunidades;

ALTER TABLE lakehouse_rotaperfume.silver.oportunidades ALTER COLUMN ganha
  COMMENT 'Derivada de etapa = "Fechado ganho". Escrever "Ganha" aqui daria zero em toda linha -- confira sempre com SELECT DISTINCT etapa.';

-- ---------------------------------------------------------------------------

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.visitas
COMMENT 'Visitas comerciais tipadas, com o resultado normalizado e a duracao em minutos.'
AS
SELECT
  CAST(visita_id AS INT)                                       AS visita_id,
  CAST(cliente_id AS INT)                                      AS cliente_id,
  CAST(vendedor_id AS INT)                                     AS vendedor_id,
  coalesce(try_to_date(data_visita),
           try_to_date(data_visita, 'dd/MM/yyyy'))             AS data_visita,
  trim(resultado)                                              AS resultado,
  trim(resultado) = 'Com pedido'                               AS gerou_pedido,
  CAST(duracao_min AS INT)                                     AS duracao_min,
  current_timestamp()                                          AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.visitas)  AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.visitas;

-- ---------------------------------------------------------------------------

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.pagamentos
COMMENT 'Pagamentos tipados. data_pagamento nula significa titulo em aberto -- nao e sujeira, e a ausencia do fato.'
AS
WITH tipado AS (
  SELECT
    CAST(pagamento_id AS INT)                                  AS pagamento_id,
    CAST(pedido_id AS INT)                                     AS pedido_id,
    trim(forma_pagamento)                                      AS forma_pagamento,
    CAST(parcelas AS INT)                                      AS parcelas,
    CAST(valor AS DECIMAL(18,2))                               AS valor,
    CAST(taxa_pct AS DECIMAL(9,4))                             AS taxa_pct,
    CAST(valor_liquido AS DECIMAL(18,2))                       AS valor_liquido,
    coalesce(try_to_date(data_vencimento),
             try_to_date(data_vencimento, 'dd/MM/yyyy'))       AS data_vencimento,
    coalesce(try_to_date(data_pagamento),
             try_to_date(data_pagamento, 'dd/MM/yyyy'))        AS data_pagamento,
    trim(status_pagamento)                                     AS status_pagamento
  FROM lakehouse_rotaperfume.bronze.pagamentos
)
SELECT
  t.*,
  t.data_pagamento IS NOT NULL                                        AS pago,
  t.data_pagamento IS NOT NULL AND t.data_pagamento > t.data_vencimento AS pago_com_atraso,
  current_timestamp()                                                 AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.pagamentos)      AS _linhas_origem
FROM tipado t;

ALTER TABLE lakehouse_rotaperfume.silver.pagamentos ALTER COLUMN pago_com_atraso
  COMMENT 'Comparacao entre data_pagamento e data_vencimento. Falso tambem para titulo ainda nao pago -- use junto com pago.';

-- ---------------------------------------------------------------------------

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.estoque
COMMENT 'Snapshot de estoque por SKU. ruptura e derivada de saldo = 0; ruptura_origem preserva a flag que veio do ERP, para dar para comparar as duas.'
AS
SELECT
  coalesce(try_to_date(data_snapshot),
           try_to_date(data_snapshot, 'dd/MM/yyyy'))            AS data_snapshot,
  trim(sku)                                                     AS sku,
  CAST(saldo AS INT)                                            AS saldo,
  CAST(saldo AS INT) = 0                                        AS ruptura,
  upper(trim(ruptura)) = 'S'                                    AS ruptura_origem,
  current_timestamp()                                           AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.estoque)   AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.estoque;

ALTER TABLE lakehouse_rotaperfume.silver.estoque ALTER COLUMN ruptura
  COMMENT 'Derivada de saldo = 0, que e a definicao de ruptura que a gold usa.';
ALTER TABLE lakehouse_rotaperfume.silver.estoque ALTER COLUMN ruptura_origem
  COMMENT 'A flag S/N como o ERP mandou. Preservada para dar para conferir se o ERP concorda com o proprio saldo.';
