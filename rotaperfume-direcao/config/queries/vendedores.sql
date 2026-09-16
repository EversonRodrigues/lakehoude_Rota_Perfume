-- Alimenta o filtro da tela. A CHAVE e vendedor_id, nunca o nome.
--
-- `rotulo` desambigua os homonimos: quando o mesmo nome aparece em mais de um
-- vendedor_id, o id entra no rotulo. Sem isso a lista mostra duas opcoes
-- visualmente identicas e o diretor nao tem como saber qual e qual.
SELECT
  vendedor_id,
  vendedor,
  COUNT(*) AS contatos,
  CASE WHEN COUNT(*) OVER (PARTITION BY vendedor) > 1
       THEN concat(vendedor, ' (id ', vendedor_id, ')')
       ELSE vendedor
  END      AS rotulo
FROM   lakehouse_rotaperfume.gold.fila_semanal
GROUP BY vendedor_id, vendedor
ORDER BY contatos DESC, vendedor
