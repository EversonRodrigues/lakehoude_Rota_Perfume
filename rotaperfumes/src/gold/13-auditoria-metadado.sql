-- =========================================================================
-- A AUDITORIA DE METADADO
--
-- Metadado faltando e BUG, nao pendencia de documentacao. O argumento nao e
-- estetico:
--
--   * o Genie escolhe a coluna pelo COMMENT. Sem COMMENT ele escolhe pelo
--     NOME -- e `valor_liquido` e `valor` viram a mesma coisa para ele;
--   * o dashboard mostra o nome da coluna. Quem abre na segunda nao sabe se
--     `receita` e bruta ou liquida, com ou sem devolucao;
--   * quem chega no projeto seis meses depois so tem isto.
--
-- Por isso a regra mora numa TAREFA que quebra o job, e nao num checklist de
-- revisao. Checklist e opcional; job vermelho nao e.
--
-- ESCOPO: schema `gold` -- a camada que alguem de fora consome. Bronze fica de
-- fora por doutrina (bronze e o dado como chegou, sem interpretacao). Silver
-- ainda tem 97 colunas sem COMMENT: e a proxima divida a pagar, e ate la
-- ampliar o escopo daqui deixaria o job permanentemente vermelho.
--
-- MECANICA: raise_error() retorna o tipo NOTHING e nao pode ficar sozinho num
-- SELECT -- vive dentro de CASE WHEN <condicao boa> THEN ... ELSE raise_error().
--
-- A mensagem de erro NOMEIA tabela.coluna. Auditoria que so diz "faltou
-- COMMENT em 7 colunas" transfere o trabalho de volta para quem le o log.
-- =========================================================================

-- 1 · Toda COLUNA da gold tem COMMENT.
SELECT 'auditoria 1 · toda coluna da gold tem COMMENT'                  AS teste,
       sem_comment                                                     AS calculado,
       0                                                               AS esperado,
       CASE WHEN sem_comment = 0 THEN 'PASSOU'
            ELSE raise_error(concat(sem_comment,
                 ' coluna(s) da gold sem COMMENT: ', quais,
                 ' -- documente na instrucao ALTER TABLE ... ALTER COLUMN ... COMMENT do arquivo que cria a tabela.'))
       END                                                              AS resultado
FROM (SELECT count(*)                                              AS sem_comment,
             concat_ws(', ', sort_array(collect_list(alvo)))        AS quais
      FROM (SELECT concat(table_name, '.', column_name) AS alvo
            FROM   lakehouse_rotaperfume.information_schema.columns
            WHERE  table_schema = 'gold'
              AND  (comment IS NULL OR trim(comment) = '')));

-- 2 · Toda TABELA da gold tem COMMENT. Coluna documentada em tabela anonima
--     nao ajuda ninguem a achar a tabela.
SELECT 'auditoria 2 · toda tabela da gold tem COMMENT'                  AS teste,
       sem_comment                                                     AS calculado,
       0                                                               AS esperado,
       CASE WHEN sem_comment = 0 THEN 'PASSOU'
            ELSE raise_error(concat(sem_comment,
                 ' tabela(s) da gold sem COMMENT: ', quais,
                 ' -- o COMMENT vai entre o CREATE OR REPLACE TABLE e o AS.'))
       END                                                              AS resultado
FROM (SELECT count(*)                                              AS sem_comment,
             concat_ws(', ', sort_array(collect_list(table_name)))  AS quais
      FROM   lakehouse_rotaperfume.information_schema.tables
      WHERE  table_schema = 'gold'
        AND  (comment IS NULL OR trim(comment) = ''));
