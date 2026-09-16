-- Quanto da fila cada vendedor ja trabalhou. Escrita AGORA, consumida na
-- entrega seguinte (a aba Acompanhamento), quando existir retorno registrado.
--
-- No comeco da semana `trabalhados` e zero para todo mundo, e a tela precisa
-- dizer isso em vez de parecer quebrada.
--
-- Chave por vendedor_id; o nome e so rotulo.
WITH ultimo_retorno AS (
  SELECT cliente_id, status
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
  COUNT_IF(r.status = 'nao_atendeu')               AS nao_atendeu
FROM   lakehouse_rotaperfume.gold.fila_semanal f
LEFT   JOIN ultimo_retorno r ON r.cliente_id = f.cliente_id
GROUP  BY f.vendedor_id, f.vendedor
ORDER  BY trabalhados DESC, na_fila DESC
