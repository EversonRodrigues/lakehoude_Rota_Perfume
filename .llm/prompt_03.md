# Prompt 3 · Silver — a limpeza com contrato

**Entrega:** as 10 tabelas silver, limpas e tipadas, com as regras de qualidade
declaradas como constraint. **Deploy nº 3.**

> **A entrega mais importante da noite. Não corte.** É aqui que 73% da sala
> — que já trabalha com dados — decide se a aula valeu.

---

## O que mostrar antes

Esta é a hora de mostrar a sujeira **com número**, não com adjetivo. Cinco
queries na bronze, quatro minutos, e a sala inteira entende o que vem pela
frente.

```sql
-- 1 · o mesmo CNPJ, escrito de três jeitos
SELECT cliente_id, cnpj, razao_social, data_cadastro
FROM lakehouse_rotaperfume.bronze.clientes
WHERE cnpj LIKE '%.%' OR cnpj <> trim(cnpj) OR cnpj LIKE '0%'
LIMIT 10;

-- 2 · quanta sujeira existe, em número
SELECT
  COUNT(*)                                                   AS clientes,
  COUNT(DISTINCT lpad(regexp_replace(trim(cnpj),'[^0-9]',''), 14, '0')) AS cnpj_unicos,
  COUNT(*) FILTER (WHERE cnpj LIKE '%.%')                    AS pontuados,
  COUNT(*) FILTER (WHERE cnpj <> trim(cnpj))                 AS com_espaco,
  COUNT(*) FILTER (WHERE data_cadastro LIKE '%/%')           AS data_br
FROM lakehouse_rotaperfume.bronze.clientes;
-- 3.040 clientes para 3.000 CNPJs: 40 empresas cadastradas duas vezes

-- 3 · as datas em dois formatos, no mesmo campo
SELECT COUNT(*) FILTER (WHERE data_pedido LIKE '%/%')     AS formato_br,
       COUNT(*) FILTER (WHERE data_pedido LIKE '____-__-__') AS formato_iso
FROM lakehouse_rotaperfume.bronze.pedidos;

-- 4 · a quantidade negativa que ninguém explicou para você
SELECT quantidade, COUNT(*) AS itens
FROM lakehouse_rotaperfume.bronze.itens_pedido
WHERE try_cast(quantidade AS INT) < 0
GROUP BY quantidade ORDER BY try_cast(quantidade AS INT);
-- 2.327 itens. É devolução — e a decisão do que fazer com eles é sua.

-- 5 · o pedido cancelado, que ficou com valor zero e nenhuma flag no item
SELECT status, COUNT(*) AS pedidos,
       ROUND(SUM(try_cast(valor_total AS DECIMAL(18,2))), 2) AS valor
FROM lakehouse_rotaperfume.bronze.pedidos
GROUP BY status ORDER BY pedidos DESC;
-- 957 cancelados com valor 0,00 — e os ITENS deles continuam lá dentro
```

**E o erro que vale mais que as cinco queries juntas**, porque é o que derruba
pipeline em produção:

```sql
SELECT date_trunc('month', to_date(data_pedido)) FROM lakehouse_rotaperfume.bronze.pedidos;
-- [CAST_INVALID_INPUT] The value '15/10/2025' ... cannot be cast to "DATE"
```

> *"Esse erro é bom. Ele aparece na sua cara. O ruim é o outro: o banco que
> devolve NULL calado e você descobre três meses depois, numa reunião, que o
> mês de outubro sumiu do relatório."*

---

**Enquanto ele trabalha, você explica:**

- **A devolução é a decisão da noite.** Quantidade negativa em `itens_pedido`
  não é erro, é devolução. Três caminhos, e cada um dá um número diferente para
  o diretor:

  ```sql
  SELECT
    -- caminho 1: descartar a devolução → o faturamento INFLA
    ROUND(SUM(try_cast(valor_bruto AS DECIMAL(18,2)))
          FILTER (WHERE try_cast(quantidade AS INT) > 0), 2)  AS descartando,
    -- caminho 2 e 3: manter tudo. A diferença é só se existe flag para separar
    ROUND(SUM(try_cast(valor_bruto AS DECIMAL(18,2))), 2)     AS mantendo_tudo,
    COUNT(*) FILTER (WHERE try_cast(quantidade AS INT) < 0)   AS itens_devolvidos
  FROM lakehouse_rotaperfume.bronze.itens_pedido;
  ```

  A distância entre as duas primeiras colunas passa de **um milhão de reais**.
  Descartar infla o faturamento; manter sem flag polui toda soma da empresa.
  **Sinalizar e deixar a análise decidir** é o único caminho que preserva os
  dois números — e é o que a coluna `devolucao` faz.

- **Deduplicar não é `DISTINCT`.** São 40 CNPJs com dois cadastros, e o
  `cliente_id` é diferente em cada um — então `DISTINCT` devolve as duas linhas,
  achando que são clientes diferentes:

  ```sql
  -- o mesmo CNPJ, dois cadastros, escritos de formas diferentes
  WITH normalizado AS (
    SELECT cliente_id, razao_social, data_cadastro,
           lpad(regexp_replace(trim(cnpj), '[^0-9]', ''), 14, '0') AS cnpj_limpo
    FROM lakehouse_rotaperfume.bronze.clientes
  )
  SELECT cnpj_limpo, collect_list(cliente_id) AS ids, COUNT(*) AS cadastros
  FROM normalizado GROUP BY cnpj_limpo HAVING COUNT(*) > 1
  ORDER BY cnpj_limpo LIMIT 5;
  -- 40 CNPJs, 80 linhas. DISTINCT não tira nenhuma delas.
  ```

  A saída é `row_number()` por CNPJ mantendo o cadastro **mais antigo** — e
  guardando o id descartado em `cliente_ids_duplicados`, porque os pedidos
  antigos continuam apontando para ele.

- **`try_to_date`, nunca `to_date`.** O Databricks SQL roda em ANSI mode: data
  malformada não vira nulo, ela **aborta a query**. Mostre os dois ao vivo:

  ```sql
  SELECT date_trunc('month', to_date(data_pedido)) AS mes
  FROM lakehouse_rotaperfume.bronze.pedidos GROUP BY 1;
  -- [CAST_INVALID_INPUT] The value '15/10/2025' of the type "STRING"
  -- cannot be cast to "DATE" because it is malformed.

  SELECT coalesce(try_to_date(data_pedido),
                  try_to_date(data_pedido, 'dd/MM/yyyy')) AS dia, COUNT(*)
  FROM lakehouse_rotaperfume.bronze.pedidos GROUP BY 1 ORDER BY 1 LIMIT 5;
  -- roda. E o coalesce dos dois formatos não deixa NENHUMA data para trás.
  ```

  Esse detalhe derruba pipeline em produção: a query passou meses funcionando e
  morre no dia em que o ERP mandou uma data no outro formato.

- **Constraint é contrato, não comentário.** `ALTER TABLE ... ADD CONSTRAINT`
  faz o Delta **recusar a escrita** que violar a regra — a regra passa a ser da
  tabela, não do script que rodou naquele dia. Prove isso em quatro linhas, numa
  tabela descartável, antes mesmo da silver ficar pronta:

  ```sql
  CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver._contrato_demo (cnpj STRING);
  ALTER TABLE lakehouse_rotaperfume.silver._contrato_demo
    ADD CONSTRAINT cnpj_14 CHECK (length(cnpj) = 14);

  INSERT INTO lakehouse_rotaperfume.silver._contrato_demo VALUES ('12345678000199'); -- ok
  INSERT INTO lakehouse_rotaperfume.silver._contrato_demo VALUES ('123');
  -- [DELTA_VIOLATE_CONSTRAINT] CHECK constraint cnpj_14 (length(cnpj) = 14) violated

  DROP TABLE lakehouse_rotaperfume.silver._contrato_demo;
  ```

  *"Repara que eu não escrevi nenhum `IF`. Quem recusou foi a tabela. Daqui a
  dois anos, quando o script que fez isso já tiver sido reescrito três vezes, a
  regra continua lá."*

---

## O prompt

```
Continue o bundle em aulas/aula-02-engenharia-de-dados/rotaperfume/.
A bronze está pronta. Agora a silver: limpar, tipar e declarar o contrato.

Crie os arquivos em src/silver/, um por assunto, em SQL (rodam como sql_task
no warehouse 666be37e3fededf2). Use CREATE OR REPLACE TABLE
lakehouse_rotaperfume.silver.{tabela}.

ATENÇÃO — armadilha já medida neste workspace: ANSI mode está ligado.
to_date() e date_trunc() sobre data malformada ABORTAM a query com
CAST_INVALID_INPUT, não retornam NULL. Use try_to_date() em toda conversão
de data, sempre.

01-clientes.sql
- cnpj vem em três formatos: puro, pontuado e com espaço em volta.
  Normalize para 14 dígitos: trim, depois regexp_replace tirando não-dígito,
  depois lpad com zero à esquerda. Nunca converta CNPJ para número.
- razao_social tem caixa e espaçamento inconsistentes. Padronize com initcap
  e colapse espaço duplo.
- data_cadastro vem em ISO e em dd/MM/yyyy misturados: coalesce de dois
  try_to_date.
- 40 CNPJs têm dois cliente_id. Deduplique com row_number() por cnpj,
  mantendo o cadastro MAIS ANTIGO. Guarde cliente_ids_duplicados (array) para
  rastreabilidade — os pedidos antigos apontam para o id descartado.
- ativo: de 'S'/'N' para boolean.

02-pedidos.sql
- data_pedido nos dois formatos, mesmo tratamento.
- valor_total é texto: CAST para DECIMAL(18,2).
- pedido cancelado tem valor zerado sem flag clara: crie a coluna booleana
  cancelado a partir do status.
- crie valor_liquido: zero quando cancelado, valor_total caso contrário.
- crie ano e mes a partir da data.

03-itens-e-produtos.sql
- produtos: tipos certos, data_lancamento com try_to_date, ativo boolean.
- itens_pedido: quantidade negativa é DEVOLUÇÃO, não erro. Crie devolucao
  (boolean) e quantidade_abs (int). NÃO descarte essas linhas.
- join com produtos para marcar sku_descontinuado quando o produto não está
  mais ativo.

04-crm-e-financeiro.sql
- vendedores, carteira, oportunidades, visitas, pagamentos, estoque.
- carteira: existe vendedor desligado com carteira vigente. Não conserte o
  dado — crie a coluna vigente, que respeita data_fim E data_desligamento, e
  a coluna orfao_vendedor_desligado, que EXPÕE o problema para o gestor.
- oportunidades: as etapas na origem se chamam 'Fechado ganho' e
  'Fechado perdido'. NÃO são 'Ganha' e 'Perdida' — confira antes de escrever
  o CASE, com um SELECT DISTINCT etapa.
- estoque: ruptura como boolean a partir de saldo = 0.

EM TODAS as tabelas silver:
- colunas de auditoria _processado_em e _linhas_origem
- COMMENT na tabela e nas colunas que exigiram decisão de limpeza,
  dizendo o que foi feito e por quê
- depois do CREATE, declare o contrato com
  ALTER TABLE ... ADD CONSTRAINT ... CHECK (...):
    silver.clientes     → length(cnpj) = 14
    silver.clientes     → data_cadastro IS NOT NULL
    silver.pedidos      → data_pedido IS NOT NULL
    silver.pedidos      → NOT cancelado OR valor_liquido = 0
    silver.itens_pedido → quantidade_abs > 0

  ATENÇÃO À QUARTA. A regra intuitiva seria `valor_liquido >= 0`, e ela FALHA:
  135 pedidos têm valor negativo. Não é sujeira — os 135 contêm item devolvido,
  e o saldo do pedido virou negativo. Negócio legítimo. A constraint certa é a
  que está escrita acima: pedido cancelado tem que ter valor ZERO.

  Se uma constraint falhar ao ser adicionada, ela fez o trabalho dela: virou
  uma suposição sua em pergunta, antes de ela virar número no dashboard.

Escreva o caminho COMPLETO das tabelas no SQL (lakehouse_rotaperfume.silver.x).
`sql_task` não substitui identificador por parâmetro, e SQL legível vale mais
numa aula do que IDENTIFIER(:catalog || '.silver.x').

Acrescente ao resources/pipeline.job.yml quatro tarefas sql_task, todas com
depends_on: bronze_ingestao. Elas rodam EM PARALELO entre si — nenhuma
depende da outra, e é o formato que o DAG desenha melhor na tela.

Rode e me mostre a saída:
  databricks bundle deploy --target dev --profile projeto-dados-ia
  databricks bundle run rotaperfume_pipeline --target dev --profile projeto-dados-ia

O QUE PRECISA BATER (medido na noite 1, com seed 42):
  3.443 datas em dd/MM/yyyy convertidas · 1.111 CNPJ pontuados
  223 CNPJ com espaço · 309 CNPJ com zero à esquerda
  40 CNPJ duplicados → 3.000 clientes únicos no final
  2.327 itens de devolução · 957 pedidos cancelados
  76 itens com SKU descontinuado · 441 carteiras de vendedor desligado
```

---

## Como verificar a feature

Cinco verificações. A terceira é o coração da noite, e a quinta é a que a sala
não esquece.

**1 · A deduplicação funcionou — e é o mesmo número por dois caminhos**

```sql
SELECT COUNT(*) AS total, COUNT(DISTINCT cnpj) AS unicos
FROM lakehouse_rotaperfume.silver.clientes;
-- 3.000 e 3.000. Os dois têm que ser IGUAIS.

-- e os 40 descartados não sumiram: continuam rastreáveis
SELECT cliente_id, cnpj, razao_social, cliente_ids_duplicados
FROM lakehouse_rotaperfume.silver.clientes
WHERE cliente_ids_duplicados IS NOT NULL AND size(cliente_ids_duplicados) > 0
LIMIT 5;
-- 40 linhas com o id antigo guardado — os pedidos velhos apontam para ele
```

**2 · A limpeza fez o que prometeu, em número**

```sql
SELECT
  COUNT(*)                                              AS clientes,
  COUNT(*) FILTER (WHERE length(cnpj) = 14)             AS cnpj_com_14_digitos,
  COUNT(*) FILTER (WHERE cnpj LIKE '%.%' OR cnpj <> trim(cnpj)) AS ainda_sujos,
  COUNT(*) FILTER (WHERE data_cadastro IS NULL)         AS data_nula
FROM lakehouse_rotaperfume.silver.clientes;
-- 3.000 · 3.000 · 0 · 0
```

| O que aparece | Valor | Query |
|---|---|---|
| Clientes únicos | **3.000** | `SELECT COUNT(*) FROM silver.clientes` |
| CNPJ ainda sujo | **0** | `... FILTER (WHERE cnpj LIKE '%.%' OR cnpj <> trim(cnpj))` |
| Itens de devolução | **2.327** | `SELECT COUNT(*) FROM silver.itens_pedido WHERE devolucao` |
| Pedidos cancelados | **957** | `SELECT COUNT(*) FROM silver.pedidos WHERE cancelado` |
| Itens com SKU descontinuado | **76** | `SELECT COUNT(*) FROM silver.itens_pedido WHERE sku_descontinuado` |
| Carteiras de vendedor desligado | **441** | `SELECT COUNT(*) FROM silver.carteira WHERE orfao_vendedor_desligado` |

```sql
SELECT
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.silver.itens_pedido WHERE devolucao)             AS devolucoes,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.silver.pedidos      WHERE cancelado)             AS cancelados,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.silver.itens_pedido WHERE sku_descontinuado)     AS sku_descontinuado,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.silver.carteira     WHERE orfao_vendedor_desligado) AS carteira_orfa;
```

**3 · O teste que importa mais: a limpeza NÃO mudou o faturamento**

```sql
SELECT
  (SELECT ROUND(SUM(try_cast(valor_total AS DECIMAL(18,2))), 2)
     FROM lakehouse_rotaperfume.bronze.pedidos
     WHERE status <> 'Cancelado')                    AS bronze_como_veio,
  (SELECT ROUND(SUM(valor_liquido), 2)
     FROM lakehouse_rotaperfume.silver.pedidos)      AS silver_limpa;
-- R$ 102.303.828,05 nas duas colunas — o MESMO número da noite 1
```

> *"Eu joguei fora 40 cadastros duplicados, converti 3.443 datas e marquei 2.327
> devoluções. O faturamento não mudou um centavo. É esse o teste de uma boa
> limpeza."*

**4 · O contrato existe, e é da tabela — não do script**

```sql
SHOW TBLPROPERTIES lakehouse_rotaperfume.silver.clientes;
-- procure as linhas delta.constraints.*  →  o CHECK está gravado na tabela

SHOW TBLPROPERTIES lakehouse_rotaperfume.silver.pedidos;
SHOW TBLPROPERTIES lakehouse_rotaperfume.silver.itens_pedido;
```

**5 · A prova de que o contrato tem dente — tente violar ao vivo**

> **Escreva a lista de colunas.** `SELECT * REPLACE (...)` **não faz parse** no
> SQL Warehouse (`PARSE_SYNTAX_ERROR` no `(` depois do `REPLACE`) — a lista
> explícita também deixa mais claro, na aula, qual coluna está sendo forçada.

```sql
-- pegue um pedido cancelado de verdade e tente regravá-lo com valor diferente de zero
INSERT INTO lakehouse_rotaperfume.silver.pedidos
SELECT pedido_id, cliente_id, vendedor_id, data_pedido, ano, mes, canal, status,
       cancelado, valor_total,
       CAST(999.00 AS DECIMAL(18,2)) AS valor_liquido,   -- <- a regra proíbe isto
       _processado_em, _linhas_origem
FROM lakehouse_rotaperfume.silver.pedidos
WHERE cancelado
LIMIT 1;
-- [DELTA_VIOLATE_CONSTRAINT_WITH_VALUES] CHECK constraint pedido_cancelado_zerado
-- ((NOT cancelado) OR (valor_liquido = 0)) violated by row with values:
--  - cancelado : true
--  - valor_liquido : 999.00
--
-- A escrita foi RECUSADA. Nenhuma linha entrou: a tabela está intacta.
SELECT COUNT(*) FROM lakehouse_rotaperfume.silver.pedidos;   -- 28.729, o mesmo de antes
```

```sql
-- agora a mesma escrita respeitando a regra — essa passa.
-- o _processado_em datado de 1999 é só para achar a linha e desfazer depois.
INSERT INTO lakehouse_rotaperfume.silver.pedidos
SELECT pedido_id, cliente_id, vendedor_id, data_pedido, ano, mes, canal, status,
       cancelado, valor_total,
       CAST(0.00 AS DECIMAL(18,2)) AS valor_liquido,      -- <- agora respeita a regra
       TIMESTAMP'1999-01-01 00:00:00' AS _processado_em,
       _linhas_origem
FROM lakehouse_rotaperfume.silver.pedidos
WHERE cancelado
LIMIT 1;
-- num_inserted_rows: 1 · a mesma porta que recusou a linha errada deixou esta passar

SELECT COUNT(*) FROM lakehouse_rotaperfume.silver.pedidos
WHERE _processado_em = TIMESTAMP'1999-01-01 00:00:00';   -- 1 · entrou

DELETE FROM lakehouse_rotaperfume.silver.pedidos
WHERE _processado_em = TIMESTAMP'1999-01-01 00:00:00';   -- desfaz, a gold não pode herdar isso
```

> **Não pule o segundo INSERT.** Mostrar só o erro ensina que constraint atrapalha.
> Mostrar os dois ensina o que ela é: uma porta que deixa passar o dado certo e
> fecha para o errado — sem depender de ninguém lembrar da regra.

---

## Fala de aula

> *"Esse é o número que a gente achou ontem: cento e dois milhões, trezentos e
> três mil. Eu acabei de jogar fora quarenta cadastros duplicados, converter
> três mil e quatrocentas datas e marcar duas mil e trezentas devoluções — e o
> faturamento não mudou um centavo.*
>
> *É esse o teste de uma boa limpeza: **ela não pode mudar o faturamento.** Se
> mudou, você jogou dado fora sem querer. E aí, três meses depois, alguém compara
> dois relatórios numa reunião e a discussão vira sobre qual sistema está certo."*

> **Sobre a devolução:** *"Repara que eu não joguei a devolução fora. Se eu
> jogasse, a receita subiria e o diretor comemoraria um número errado. Se eu
> deixasse sem flag, toda soma ficaria poluída. A resposta certa é a terceira:
> sinaliza, e deixa quem faz a análise decidir se quer o bruto ou o líquido."*


---

## Se der errado ao vivo

| Sintoma | Causa | Correção em um prompt |
|---|---|---|
| `CAST_INVALID_INPUT` e a query morre | Usou `to_date` em vez de `try_to_date` | ANSI mode está ligado: data malformada **aborta**, não vira nulo |
| `DELTA_NEW_CHECK_CONSTRAINT_VIOLATION: 135 rows` | A constraint `valor_liquido >= 0` está errada | Os 135 são pedidos com devolução. Troque por `NOT cancelado OR valor_liquido = 0` |
| `ganha` deu 0 em toda linha | A etapa é `Fechado ganho`, não `Ganha` | *"Confira os valores reais com SELECT DISTINCT etapa e corrija o CASE."* |
| Clientes deu 3.040 e não 3.000 | A deduplicação não rodou | `row_number()` por CNPJ, `WHERE ordem = 1` |
| A receita mudou depois da limpeza | Você descartou linha sem querer | Devolução e cancelado **ficam**, com flag. Nunca some linha |
| `PARSE_SYNTAX_ERROR` no `(` depois de `REPLACE` | `SELECT * REPLACE (...)` não faz parse no SQL Warehouse | Escreva a lista de colunas explícita no `INSERT` |
| A primeira execução demora bem mais que o medido | Warehouse e compute serverless dormiram | Rode um `SELECT 1` para acordar antes de medir tempo |

**Tempo medido:** ~8s de deploy, ~3min30 de execução do job inteiro (as duas
tarefas anteriores mais as quatro silver em paralelo), com o warehouse já quente.

> **Este é o prompt mais longo da noite.** Se estiver atrasado, corte o prompt 5,
> nunca este.