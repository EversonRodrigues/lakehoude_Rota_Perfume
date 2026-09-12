-- Gold · os 9 testes que QUEBRAM o pipeline
--
-- Teste que nao quebra o job nao e teste, e relatorio. Se a verificacao falha e
-- o pipeline segue, o dashboard mostra numero errado com cara de certo -- e
-- ninguem descobre ate a reuniao de segunda.
--
-- Esta tarefa e a ULTIMA do job, e depende de todas as outras. Quando ela fica
-- vermelha, o dashboard fica com o dado de ONTEM. E de longe o melhor dos dois
-- cenarios ruins.
--
-- MECANICA: raise_error() retorna o tipo NOTHING, entao ele nao pode ficar
-- sozinho num SELECT -- vive dentro de
--   CASE WHEN <condicao boa> THEN 'PASSOU' ELSE raise_error('...') END
--
-- Se um teste falhar: corrija a TRANSFORMACAO, nunca o teste.

-- 1 · O teste que mais importa: limpar NAO PODE mudar o faturamento.
SELECT 'teste 1 · receita gold = receita silver'                       AS teste,
       gold                                                           AS calculado,
       silver                                                         AS esperado,
       CASE WHEN abs(gold - silver) <= 0.01 THEN 'PASSOU'
            ELSE raise_error(concat('receita da gold (', gold,
                 ') diferente da silver (', silver, ')')) END          AS resultado
FROM (SELECT (SELECT sum(receita)       FROM lakehouse_rotaperfume.gold.fato_vendas)  AS gold,
             (SELECT sum(valor_liquido) FROM lakehouse_rotaperfume.silver.pedidos)    AS silver);

-- 2 · Um CNPJ, um cliente. A deduplicacao da silver tem que continuar de pe.
SELECT 'teste 2 · CNPJ unico em silver.clientes'                       AS teste,
       duplicados                                                     AS calculado,
       0                                                              AS esperado,
       CASE WHEN duplicados = 0 THEN 'PASSOU'
            ELSE raise_error(concat(duplicados, ' CNPJ com mais de um cadastro')) END AS resultado
FROM (SELECT count(*) AS duplicados FROM (
        SELECT cnpj FROM lakehouse_rotaperfume.silver.clientes
        GROUP BY cnpj HAVING count(*) > 1));

-- 3 · Data de pedido nula arruina qualquer corte temporal em silencio.
SELECT 'teste 3 · nenhuma data_pedido nula'                            AS teste,
       nulas                                                          AS calculado,
       0                                                              AS esperado,
       CASE WHEN nulas = 0 THEN 'PASSOU'
            ELSE raise_error(concat(nulas, ' pedidos sem data')) END    AS resultado
FROM (SELECT count(*) AS nulas FROM lakehouse_rotaperfume.silver.pedidos
      WHERE data_pedido IS NULL);

-- 4 · Receita negativa so pode existir onde houve devolucao.
--     Se aparecer em outro lugar, e preco ou quantidade corrompidos.
SELECT 'teste 4 · receita negativa so em devolucao'                    AS teste,
       fora_do_padrao                                                 AS calculado,
       0                                                              AS esperado,
       CASE WHEN fora_do_padrao = 0 THEN 'PASSOU'
            ELSE raise_error(concat(fora_do_padrao,
                 ' linhas com receita negativa sem flag de devolucao')) END AS resultado
FROM (SELECT count(*) AS fora_do_padrao FROM lakehouse_rotaperfume.gold.fato_vendas
      WHERE receita < 0 AND NOT devolucao);

-- 5 · Volume: pega tanto a carga que veio pela metade quanto o JOIN que dobrou.
SELECT 'teste 5 · volume da fato_vendas entre 140k e 250k'             AS teste,
       linhas                                                         AS calculado,
       '140000..250000'                                               AS esperado,
       CASE WHEN linhas BETWEEN 140000 AND 250000 THEN 'PASSOU'
            ELSE raise_error(concat('fato_vendas com ', linhas,
                 ' linhas, fora da faixa esperada')) END               AS resultado
FROM (SELECT count(*) AS linhas FROM lakehouse_rotaperfume.gold.fato_vendas);

-- 6 · Integridade referencial: pedido do fato tem que existir na silver.
SELECT 'teste 6 · nenhum pedido_id orfao'                              AS teste,
       orfaos                                                         AS calculado,
       0                                                              AS esperado,
       CASE WHEN orfaos = 0 THEN 'PASSOU'
            ELSE raise_error(concat(orfaos, ' pedido_id da gold nao existem na silver')) END AS resultado
FROM (SELECT count(*) AS orfaos FROM (
        SELECT DISTINCT f.pedido_id FROM lakehouse_rotaperfume.gold.fato_vendas f
        LEFT ANTI JOIN lakehouse_rotaperfume.silver.pedidos p ON p.pedido_id = f.pedido_id));

-- 7 · O mesmo para cliente. Atencao: a silver descartou 40 cliente_id na
--     deduplicacao por CNPJ -- se algum pedido apontasse para um deles, este
--     teste acusaria. Hoje sao zero.
SELECT 'teste 7 · nenhum cliente_id orfao'                             AS teste,
       orfaos                                                         AS calculado,
       0                                                              AS esperado,
       CASE WHEN orfaos = 0 THEN 'PASSOU'
            ELSE raise_error(concat(orfaos, ' cliente_id da gold nao existem na silver')) END AS resultado
FROM (SELECT count(*) AS orfaos FROM (
        SELECT DISTINCT f.cliente_id FROM lakehouse_rotaperfume.gold.fato_vendas f
        LEFT ANTI JOIN lakehouse_rotaperfume.silver.clientes c ON c.cliente_id = f.cliente_id));

-- 8 · Conformado: o mart de produto tem que somar o mesmo que o fato.
SELECT 'teste 8 · mart_produto_performance = fato_vendas'              AS teste,
       mart                                                           AS calculado,
       fato                                                           AS esperado,
       CASE WHEN abs(mart - fato) <= 0.01 THEN 'PASSOU'
            ELSE raise_error(concat('mart soma ', mart, ' e o fato soma ', fato)) END AS resultado
FROM (SELECT (SELECT sum(receita) FROM lakehouse_rotaperfume.gold.mart_produto_performance) AS mart,
             (SELECT sum(receita) FROM lakehouse_rotaperfume.gold.fato_vendas)              AS fato);

-- 9 · O contrato do CNPJ, cobrado tambem de fora da tabela.
SELECT 'teste 9 · todo CNPJ com 14 digitos'                            AS teste,
       fora_do_formato                                                AS calculado,
       0                                                              AS esperado,
       CASE WHEN fora_do_formato = 0 THEN 'PASSOU'
            ELSE raise_error(concat(fora_do_formato, ' CNPJ sem 14 digitos')) END AS resultado
FROM (SELECT count(*) AS fora_do_formato FROM lakehouse_rotaperfume.silver.clientes
      WHERE length(cnpj) <> 14 OR cnpj RLIKE '[^0-9]');
