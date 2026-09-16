-- Gold · os tres marts
--
-- Um fato, varios marts. O erro classico e criar fato_vendas_comercial e
-- fato_vendas_produto: em tres meses eles divergem e ninguem sabe qual esta
-- certo. O que separa um mart do outro e a DIMENSAO DOMINANTE e as METRICAS --
-- nunca a tabela base. Os tres aqui leem do mesmo gold.fato_vendas, e por isso
-- somam igual. E isso que a palavra "conformado" significa.

-- --------------------------------------------------------------------------
-- Diretoria comercial: como cada vendedor foi, mes a mes, contra a meta.
CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor
COMMENT 'Grao vendedor x mes. Para a diretoria comercial: receita, margem, atingimento de meta, cobertura de carteira e ticket medio.'
AS
WITH por_vendedor_mes AS (
  SELECT
    f.vendedor_id,
    f.ano,
    f.mes,
    sum(f.receita)                        AS receita,
    sum(f.margem)                         AS margem,
    count(DISTINCT f.cliente_id)          AS clientes_atendidos,
    count(DISTINCT f.pedido_id)           AS pedidos,
    sum(f.quantidade)                     AS pecas
  FROM lakehouse_rotaperfume.gold.fato_vendas f
  GROUP BY f.vendedor_id, f.ano, f.mes
)
SELECT
  v.vendedor_id,
  d.nome                                                              AS vendedor,
  d.regiao,
  d.uf,
  d.ativo                                                             AS vendedor_ativo,
  v.ano,
  v.mes,
  v.receita,
  v.margem,
  CAST(100 * v.margem / nullif(v.receita, 0) AS DECIMAL(9,2))         AS margem_pct,
  d.meta_mensal,
  CAST(100 * v.receita / nullif(d.meta_mensal, 0) AS DECIMAL(9,2))    AS atingimento_pct,
  v.clientes_atendidos,
  v.pedidos,
  v.pecas,
  CAST(v.receita / nullif(v.pedidos, 0) AS DECIMAL(18,2))             AS ticket_medio,
  current_timestamp()                                                 AS _processado_em
FROM por_vendedor_mes v
JOIN lakehouse_rotaperfume.gold.dim_vendedor d ON d.vendedor_id = v.vendedor_id;

ALTER TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor ALTER COLUMN atingimento_pct
  COMMENT 'Receita do mes sobre a meta mensal, em porcentagem. 100 significa meta batida na risca. Compara com a meta VIGENTE, nao com a meta historica do mes.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor ALTER COLUMN ticket_medio
  COMMENT 'Receita dividida por pedidos distintos no mes. Nao e receita por item.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor ALTER COLUMN clientes_atendidos
  COMMENT 'Clientes distintos com pedido no mes. Cliente que comprou tres vezes conta uma vez.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor ALTER COLUMN vendedor
  COMMENT 'Nome do vendedor, para EXIBIR. NAO identifica a pessoa: ha nomes repetidos nesta base, e agrupar por esta coluna funde duas carteiras em uma linha so. O identificador e vendedor_id.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor ALTER COLUMN regiao
  COMMENT 'Regiao comercial do vendedor, herdada de dim_vendedor. Recorte de gestao, nao de localizacao do cliente.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor ALTER COLUMN uf
  COMMENT 'UF base do vendedor, nao a do cliente que comprou. Para geografia de venda, use a UF em fato_vendas.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor ALTER COLUMN vendedor_ativo
  COMMENT 'Vendedor na ativa hoje. Desligado continua aparecendo com o historico dele -- a venda aconteceu e nao some do faturamento.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor ALTER COLUMN receita
  COMMENT 'Soma de receita do fato no mes, em reais. Ja inclui devolucao com sinal negativo: e receita LIQUIDA. Para a bruta, filtre devolucao no fato.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor ALTER COLUMN margem
  COMMENT 'Receita menos custo no mes, em reais. Calculada uma vez so no fato, a partir do custo da dimensao de produto.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor ALTER COLUMN margem_pct
  COMMENT 'Margem sobre receita, em porcentagem. NULL quando a receita do mes e zero -- divisao protegida, nao margem zero.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor ALTER COLUMN pedidos
  COMMENT 'Pedidos distintos no mes. Pedido cancelado nao entra: o fato ja o exclui pelo contrato.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor ALTER COLUMN pecas
  COMMENT 'Soma da quantidade vendida no mes. Devolucao entra com quantidade negativa e reduz o total, de proposito.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor ALTER COLUMN _processado_em
  COMMENT 'Momento em que esta linha foi (re)gerada pelo pipeline. Metadado tecnico, nunca metrica de negocio.';

-- --------------------------------------------------------------------------
-- Diretoria de produto: quem sustenta a receita e quem sustenta a margem.
CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.mart_produto_performance
COMMENT 'Grao SKU x mes. Para a diretoria de produto: receita, margem e curva ABC. Soma o mesmo total que gold.fato_vendas -- e o teste 8.'
AS
WITH por_sku_mes AS (
  SELECT
    f.sku, f.ano, f.mes,
    sum(f.receita)                              AS receita,
    sum(f.margem)                               AS margem,
    sum(f.quantidade)                           AS quantidade,
    sum(CASE WHEN f.devolucao THEN f.quantidade ELSE 0 END) AS quantidade_devolvida
  FROM lakehouse_rotaperfume.gold.fato_vendas f
  GROUP BY f.sku, f.ano, f.mes
),
-- Curva ABC: ordena o SKU pela receita do mes e acumula a participacao.
-- A = ate 80% da receita, B = ate 95%, C = o resto.
abc AS (
  SELECT *,
    sum(receita) OVER (PARTITION BY ano, mes)                        AS receita_mes,
    sum(receita) OVER (PARTITION BY ano, mes ORDER BY receita DESC
                       ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS receita_acumulada
  FROM por_sku_mes
)
SELECT
  a.sku,
  p.descricao,
  p.marca,
  p.categoria,
  p.descontinuado,
  a.ano,
  a.mes,
  a.receita,
  a.margem,
  CAST(100 * a.margem / nullif(a.receita, 0) AS DECIMAL(9,2))        AS margem_pct,
  a.quantidade,
  a.quantidade_devolvida,
  CAST(100 * a.receita_acumulada / nullif(a.receita_mes, 0) AS DECIMAL(9,2)) AS participacao_acumulada_pct,
  CASE
    WHEN 100 * a.receita_acumulada / nullif(a.receita_mes, 0) <= 80 THEN 'A'
    WHEN 100 * a.receita_acumulada / nullif(a.receita_mes, 0) <= 95 THEN 'B'
    ELSE 'C'
  END                                                                AS curva_abc,
  current_timestamp()                                                AS _processado_em
FROM abc a
JOIN lakehouse_rotaperfume.gold.dim_produto p ON p.sku = a.sku;

ALTER TABLE lakehouse_rotaperfume.gold.mart_produto_performance ALTER COLUMN curva_abc
  COMMENT 'Classificacao por receita acumulada DENTRO DO MES: A ate 80%, B ate 95%, C o restante. Um SKU pode ser A num mes e C no seguinte -- e essa a graca da curva.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_produto_performance ALTER COLUMN margem_pct
  COMMENT 'Margem sobre receita do SKU no mes. Kit Presente fica perto de 33%, Oleo Concentrado perto de 50%.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_produto_performance ALTER COLUMN descricao
  COMMENT 'Nome comercial do produto, herdado de dim_produto. E o rotulo do relatorio; a chave e o sku.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_produto_performance ALTER COLUMN marca
  COMMENT 'Marca do fabricante. Corte principal deste mart e da analise de ruptura.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_produto_performance ALTER COLUMN categoria
  COMMENT 'Familia do produto. Recorte mais amplo que marca, usado para comparar linhas entre si.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_produto_performance ALTER COLUMN receita
  COMMENT 'Soma de receita do fato para o SKU, em reais. Liquida: devolucao ja entra com sinal negativo.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_produto_performance ALTER COLUMN margem
  COMMENT 'Receita menos custo do SKU, em reais. O custo vem de dim_produto.custo_unitario.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_produto_performance ALTER COLUMN quantidade
  COMMENT 'Pecas vendidas do SKU, ja liquidas de devolucao. Para o volume devolvido isolado, use quantidade_devolvida.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_produto_performance ALTER COLUMN participacao_acumulada_pct
  COMMENT 'Participacao acumulada na receita, do SKU mais vendido para o menos, em porcentagem. E o eixo que define a curva ABC: ate 80 e A, ate 95 e B, o resto e C.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_produto_performance ALTER COLUMN _processado_em
  COMMENT 'Momento em que esta linha foi (re)gerada pelo pipeline. Metadado tecnico, nunca metrica de negocio.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_produto_performance ALTER COLUMN quantidade_devolvida
  COMMENT 'Pecas devolvidas no mes, em numero negativo. Serve para achar SKU com devolucao fora do padrao.';

-- --------------------------------------------------------------------------
-- Diretoria financeira: o unico mart que NAO sai do fato de vendas -- ele olha
-- para o pagamento, que tem calendario proprio (vencimento, nao pedido).
CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento
COMMENT 'Grao mes de VENCIMENTO. Para a diretoria financeira: a receber, recebido, atraso medio e custo de taxa. Nao soma igual ao fato de vendas de proposito -- o calendario e o do vencimento, nao o do pedido.'
AS
SELECT
  year(pg.data_vencimento)                                           AS ano_vencimento,
  month(pg.data_vencimento)                                          AS mes_vencimento,
  pg.forma_pagamento,
  count(*)                                                           AS titulos,
  sum(pg.valor)                                                      AS valor_previsto,
  sum(CASE WHEN pg.pago THEN pg.valor ELSE 0 END)                    AS valor_recebido,
  sum(CASE WHEN NOT pg.pago THEN pg.valor ELSE 0 END)                AS valor_a_receber,
  sum(pg.valor - pg.valor_liquido)                                   AS custo_taxa,
  CAST(avg(CASE WHEN pg.pago_com_atraso
                THEN datediff(pg.data_pagamento, pg.data_vencimento) END) AS DECIMAL(9,1)) AS atraso_medio_dias,
  count(*) FILTER (WHERE pg.pago_com_atraso)                         AS titulos_em_atraso,
  current_timestamp()                                                AS _processado_em
FROM lakehouse_rotaperfume.silver.pagamentos pg
WHERE pg.data_vencimento IS NOT NULL
GROUP BY year(pg.data_vencimento), month(pg.data_vencimento), pg.forma_pagamento;

ALTER TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento ALTER COLUMN atraso_medio_dias
  COMMENT 'Media de dias entre vencimento e pagamento, considerando SO os titulos pagos com atraso. Titulo pago em dia nao entra na media e nao a puxa para baixo.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento ALTER COLUMN custo_taxa
  COMMENT 'Diferenca entre valor bruto e valor liquido do titulo: o que a operadora de pagamento reteve.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento ALTER COLUMN valor_a_receber
  COMMENT 'Titulos ainda sem data de pagamento. Ausencia de pagamento nao e sujeira: e o fato ainda nao ter acontecido.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento ALTER COLUMN ano_vencimento
  COMMENT 'Ano do VENCIMENTO do titulo, nao do pedido. E por isso que este mart nao soma igual aos de venda: o calendario e outro.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento ALTER COLUMN mes_vencimento
  COMMENT 'Mes do vencimento, de 1 a 12. O grao deste mart e mes de vencimento x forma de pagamento.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento ALTER COLUMN forma_pagamento
  COMMENT 'Meio de pagamento do titulo (boleto, cartao, pix...). Determina o custo de taxa e o prazo tipico de recebimento.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento ALTER COLUMN titulos
  COMMENT 'Quantidade de titulos que vencem no mes, nesta forma de pagamento. Contagem de documentos, nao de pedidos.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento ALTER COLUMN valor_previsto
  COMMENT 'Valor BRUTO total que vence no mes, em reais, antes da taxa da operadora. E o previsto, nao o realizado.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento ALTER COLUMN valor_recebido
  COMMENT 'Valor dos titulos ja pagos, em reais. Somado a valor_a_receber, reconstitui valor_previsto.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento ALTER COLUMN titulos_em_atraso
  COMMENT 'Titulos pagos DEPOIS do vencimento. Nao inclui titulo vencido e ainda nao pago -- esse esta em valor_a_receber.';
ALTER TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento ALTER COLUMN _processado_em
  COMMENT 'Momento em que esta linha foi (re)gerada pelo pipeline. Metadado tecnico, nunca metrica de negocio.';
