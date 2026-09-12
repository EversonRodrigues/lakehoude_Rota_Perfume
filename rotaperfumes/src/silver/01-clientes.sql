-- Silver · clientes
--
-- Tres decisoes de limpeza moram aqui, e nenhuma delas joga linha fora:
--
--   1. CNPJ vem em tres formatos na origem -- puro, pontuado e com espaco em
--      volta. Normalizamos para 14 digitos: trim, tira nao-digito, lpad com
--      zero a esquerda. NUNCA converter CNPJ para numero: o zero a esquerda
--      some e 309 clientes viram outro CNPJ.
--
--   2. data_cadastro vem em ISO e em dd/MM/yyyy misturados. try_to_date, nunca
--      to_date: o warehouse roda em ANSI mode, e data malformada ABORTA a
--      query em vez de virar nulo.
--
--   3. 40 CNPJs tem dois cliente_id diferentes. DISTINCT nao resolve -- para o
--      DISTINCT sao linhas diferentes. row_number() por CNPJ mantendo o
--      cadastro MAIS ANTIGO, e o id descartado fica guardado em
--      cliente_ids_duplicados, porque os pedidos antigos ainda apontam para ele.

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.clientes
COMMENT 'Clientes limpos e deduplicados por CNPJ. 3.040 cadastros da bronze viram 3.000 clientes; os ids descartados ficam rastreaveis em cliente_ids_duplicados.'
AS
WITH normalizado AS (
  SELECT
    CAST(cliente_id AS INT)                                            AS cliente_id,
    lpad(regexp_replace(trim(cnpj), '[^0-9]', ''), 14, '0')            AS cnpj,
    initcap(trim(regexp_replace(razao_social, '\\s+', ' ')))           AS razao_social,
    trim(segmento)                                                     AS segmento,
    trim(cidade)                                                       AS cidade,
    upper(trim(uf))                                                    AS uf,
    trim(bairro)                                                       AS bairro,
    coalesce(try_to_date(data_cadastro),
             try_to_date(data_cadastro, 'dd/MM/yyyy'))                 AS data_cadastro,
    upper(trim(ativo)) = 'S'                                           AS ativo
  FROM lakehouse_rotaperfume.bronze.clientes
),
-- Um cadastro por CNPJ: o mais antigo ganha; empate desempata pelo menor id.
ordenado AS (
  SELECT *,
         row_number() OVER (PARTITION BY cnpj ORDER BY data_cadastro, cliente_id) AS ordem
  FROM normalizado
),
-- Os ids perdedores, agrupados para voltarem como array no vencedor.
descartados AS (
  SELECT cnpj, array_agg(cliente_id) AS cliente_ids_duplicados
  FROM ordenado
  WHERE ordem > 1
  GROUP BY cnpj
)
SELECT
  o.cliente_id,
  o.cnpj,
  o.razao_social,
  o.segmento,
  o.cidade,
  o.uf,
  o.bairro,
  o.data_cadastro,
  o.ativo,
  d.cliente_ids_duplicados,
  current_timestamp()                                                  AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.clientes)          AS _linhas_origem
FROM ordenado o
LEFT JOIN descartados d ON d.cnpj = o.cnpj
WHERE o.ordem = 1;

-- Os comentarios de coluna documentam a DECISAO, nao o obvio.
ALTER TABLE lakehouse_rotaperfume.silver.clientes ALTER COLUMN cnpj
  COMMENT 'Normalizado para 14 digitos: trim + regexp_replace + lpad com zero a esquerda. Fica STRING de proposito -- como numero, 309 CNPJs perderiam o zero da frente.';
ALTER TABLE lakehouse_rotaperfume.silver.clientes ALTER COLUMN razao_social
  COMMENT 'initcap e espaco duplo colapsado. A origem mistura caixa alta, baixa e espacamento irregular.';
ALTER TABLE lakehouse_rotaperfume.silver.clientes ALTER COLUMN data_cadastro
  COMMENT 'coalesce de dois try_to_date (ISO e dd/MM/yyyy): a origem mistura os dois formatos no mesmo campo.';
ALTER TABLE lakehouse_rotaperfume.silver.clientes ALTER COLUMN cliente_ids_duplicados
  COMMENT 'Ids descartados na deduplicacao por CNPJ. NULL quando o cliente nunca teve cadastro repetido. Pedido antigo pode apontar para um id daqui.';

-- O contrato. Quem passa a recusar a escrita errada e a tabela, nao o script.
ALTER TABLE lakehouse_rotaperfume.silver.clientes
  ADD CONSTRAINT cnpj_14_digitos CHECK (length(cnpj) = 14);
ALTER TABLE lakehouse_rotaperfume.silver.clientes
  ADD CONSTRAINT data_cadastro_obrigatoria CHECK (data_cadastro IS NOT NULL);
