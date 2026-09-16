-- @param vendedor_id STRING = Todos
--
-- A fila da semana, com o retorno mais recente de cada cliente pendurado.
--
-- O filtro e por vendedor_id e NAO por nome -- ha nome repetido nesta base, e
-- filtrar por nome juntaria a carteira de duas pessoas diferentes numa lista
-- so. 'Todos' e o sentinel que nao filtra.
--
-- O LEFT JOIN tem que sobreviver a tabela de retorno VAZIA: no comeco da
-- semana ela tem zero linhas e toda coluna de retorno volta NULL, que e o
-- estado correto.
WITH ultimo_retorno AS (
  SELECT cliente_id, status, comentario, registrado_em, registrado_por
  FROM   lakehouse_rotaperfume.gold.retorno_ligacao
  QUALIFY ROW_NUMBER() OVER (PARTITION BY cliente_id ORDER BY registrado_em DESC) = 1
)
SELECT
  f.ordem,
  f.cliente_id,
  f.razao_social,
  f.cidade,
  f.uf,
  f.ticket_medio,
  f.vendedor_id,
  f.vendedor,
  f.score,
  f.faixa,
  f.motivo,
  f.sugestao,
  r.status         AS retorno_status,
  r.comentario     AS retorno_comentario,
  r.registrado_em  AS retorno_em
FROM   lakehouse_rotaperfume.gold.fila_semanal f
LEFT   JOIN ultimo_retorno r ON r.cliente_id = f.cliente_id
-- O CAST e do lado da COLUNA, de proposito. `f.vendedor_id = :vendedor_id`
-- com a coluna INT e o parametro STRING faz o DBSQL tentar converter 'Todos'
-- para numero, e em modo ANSI isso ABORTA a query com CAST_INVALID_INPUT --
-- nao ha garantia de curto-circuito no OR. Comparando texto com texto, o
-- sentinel nunca vira um cast.
WHERE  :vendedor_id = 'Todos' OR CAST(f.vendedor_id AS STRING) = :vendedor_id
ORDER  BY f.score DESC
