-- Os quatro numeros do topo da tela, numa linha so.
--
-- `vendedores` conta DISTINCT vendedor_id, nunca o nome: dois vendedores desta
-- base tem nome repetido (36 por id contra 35 por nome). Contar por nome some
-- com uma pessoa em silencio.
--
-- `modelo_metricas` guarda uma linha por treino; QUALIFY pega a versao mais
-- recente. `receita_esperada` e ESTIMATIVA -- soma de probabilidade vezes
-- ticket historico, nao receita realizada.
SELECT
  fila.contatos,
  fila.vendedores,
  fila.receita_esperada,
  fila.referencia,
  m.acertos_top200,
  m.lift_top200,
  m.taxa_base,
  m.versao                                   AS versao_modelo,
  r.retornos,
  r.viraram_pedido
FROM (
  SELECT COUNT(*)                            AS contatos,
         COUNT(DISTINCT vendedor_id)         AS vendedores,
         ROUND(SUM(score * ticket_medio), 2) AS receita_esperada,
         MAX(_gerada_em)                     AS referencia
  FROM   lakehouse_rotaperfume.gold.fila_semanal
) fila
CROSS JOIN (
  SELECT acertos_top200, lift_top200, taxa_base, versao
  FROM   lakehouse_rotaperfume.gold.modelo_metricas
  QUALIFY ROW_NUMBER() OVER (ORDER BY versao DESC) = 1
) m
CROSS JOIN (
  -- Um cliente pode ter varios retornos: o estado atual e o mais recente.
  SELECT COUNT(*)                            AS retornos,
         COUNT_IF(status = 'vendeu')         AS viraram_pedido
  FROM (
    SELECT cliente_id, status
    FROM   lakehouse_rotaperfume.gold.retorno_ligacao
    QUALIFY ROW_NUMBER() OVER (PARTITION BY cliente_id ORDER BY registrado_em DESC) = 1
  )
) r
