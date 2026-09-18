# Prompt 4 · Gold — os data marts e os testes que quebram o pipeline

> **Antes de colar:** troque `<PERFIL>`, `<WAREHOUSE_ID>` e `<HOST_DO_WORKSPACE>`
> pelos valores do seu ambiente — a tabela está em
> [prompts/README.md](../README.md#as-variáveis).


**Entrega:** dimensões conformadas, `fato_vendas`, três marts por diretoria e
os 9 testes de qualidade que interrompem o job. **Deploy nº 4.**

> A Gold não é "a camada limpa" — isso é a silver. A Gold é a camada **modelada
> para um consumidor específico**. Se você não sabe quem consome, não está
> pronto para criar Gold.

---

## O que mostrar antes

A silver está limpa — e mesmo assim a pergunta simples continua cara. É esse o
argumento da gold, e ele só funciona se a sala VIR a query feia primeiro.

**1 · A gold está vazia**

```sql
SHOW TABLES IN lakehouse_rotaperfume.gold;   -- nada
```

**2 · "Receita por marca nos últimos 6 meses" — direto da silver**

```sql
SELECT pr.marca,
       ROUND(SUM(i.quantidade * i.preco_praticado), 2) AS receita
FROM lakehouse_rotaperfume.silver.itens_pedido i
JOIN lakehouse_rotaperfume.silver.pedidos  p ON p.pedido_id = i.pedido_id
JOIN lakehouse_rotaperfume.silver.produtos pr ON pr.sku = i.sku
WHERE NOT p.cancelado
  AND p.data_pedido >= add_months(current_date(), -6)
GROUP BY pr.marca
ORDER BY receita DESC
LIMIT 5;
```

**Três `JOIN` e duas regras de negócio escondidas dentro do `WHERE`.** Pergunte
para a sala: *"quantas pessoas na sua empresa escreveriam esse `WHERE NOT
p.cancelado`? E quantas esqueceriam?"* Cada esquecimento é um relatório com
número diferente na mesma reunião.

**3 · A pergunta que ninguém consegue responder ainda**

```sql
-- "qual é a margem por categoria?" — a silver não sabe: custo está em produtos,
-- receita está em itens, e a regra de margem não existe em lugar nenhum.
SELECT pr.categoria,
       ROUND(SUM(i.quantidade * i.preco_praticado), 2)                        AS receita,
       ROUND(SUM(i.quantidade * i.preco_praticado - i.quantidade * pr.custo_unitario), 2) AS margem
FROM lakehouse_rotaperfume.silver.itens_pedido i
JOIN lakehouse_rotaperfume.silver.pedidos  p  ON p.pedido_id = i.pedido_id
JOIN lakehouse_rotaperfume.silver.produtos pr ON pr.sku = i.sku
WHERE NOT p.cancelado
GROUP BY pr.categoria ORDER BY margem;
```

> *"Essa regra de margem — receita menos custo, sem frete, sem desconto
> comercial — acabou de ser inventada por mim, agora, nessa query. Amanhã outra
> pessoa inventa outra. A gold existe para essa frase ser escrita **uma vez**,
> numa coluna com COMMENT, e valer para a empresa inteira."*

---

**Enquanto ele trabalha, você explica:**

- **O contrato vem antes do SQL.** Granularidade, dimensões, métricas e filtros
  definidos **antes** da primeira linha. `fato_vendas` tem grão de *item de
  pedido* — escrever isso numa frase evita seis meses de discussão.
- **Um fato, vários marts.** O erro clássico é criar `fato_vendas_comercial` e
  `fato_vendas_produto`. Em três meses eles divergem e ninguém sabe qual está
  certo. O que separa um mart do outro é a **dimensão dominante** e as
  **métricas**, nunca a tabela base.
- **Conformado significa que somam igual.** Os três marts têm que fechar no
  mesmo R$ 102.303.828,05. É esse o significado da palavra.
- **Teste que não quebra o job não é teste, é relatório.** Se a verificação
  falha e o pipeline segue, o dashboard mostra número errado com cara de certo.

---

## O prompt

```
Continue o bundle em aulas/aula-02-engenharia-de-dados/rotaperfume/.
A silver está limpa e com contrato. Agora a gold: modelar para consumo.

Crie em src/gold/, em SQL, lendo SÓ da silver — nunca da bronze.

05-dimensoes.sql — quatro dimensões conformadas
  gold.dim_cliente    uma linha por cliente: segmento, cidade, uf, data de
                      cadastro, data do primeiro e do último pedido, total de
                      pedidos, receita acumulada, dias desde a última compra
  gold.dim_produto    uma linha por SKU: marca, categoria, nota olfativa,
                      custo, preço de tabela, data de lançamento, descontinuado
  gold.dim_vendedor   uma linha por vendedor: região, meta mensal, ativo
  gold.dim_calendario uma linha por dia dos 24 meses: ano, mes, nome do mês,
                      trimestre, dia da semana, e a coluna mes_pico_setor
                      (abril, junho e outubro = TRUE)

06-fato-vendas.sql — o contrato, escrito antes do SQL num comentário no topo
  Granularidade: uma linha por ITEM de pedido
  Filtro: exclua pedidos cancelados. NÃO exclua devolução.
  Dimensões: data_pedido, ano, mes, canal, cliente_id, razao_social, segmento,
             cidade, vendedor_id, sku, categoria, marca, nota_olfativa
  Métricas:  quantidade, preco_praticado, receita, custo, margem, devolucao
  custo  = quantidade * custo_unitario do produto
  margem = receita - custo
  Devolução entra com quantidade e receita NEGATIVAS, com a flag devolucao.
  Particione por ano e mes.

  POR QUE A DEVOLUÇÃO FICA DENTRO: se ela ficar de fora, a gold soma
  R$ 103,6 mi e a silver R$ 102,3 mi. R$ 1,26 milhão de diferença entre duas
  camadas do mesmo pipeline. Quem quiser o bruto pede:
    SUM(receita) FILTER (WHERE NOT devolucao)

07-marts.sql — um mart por diretoria, todos sobre o MESMO fato
  gold.mart_vendas_por_vendedor   grão vendedor × mês: receita, margem, meta,
                                  atingimento, clientes atendidos, ticket médio
  gold.mart_produto_performance   grão SKU × mês: receita, margem, margem %,
                                  quantidade, curva ABC por receita acumulada
  gold.mart_financeiro_recebimento grão mês de vencimento: valor a receber,
                                  recebido, atraso médio, custo de taxa

COMMENT em TODAS as tabelas, e em TODAS as colunas de fato_vendas, explicando
o significado de NEGÓCIO, não o técnico. Por exemplo, em margem:
"Receita menos custo do produto. Não considera desconto comercial nem frete."
Nas dimensões, comente as colunas que exigiram decisão (dias_sem_comprar,
mes_pico_setor); cidade e uf se explicam sozinhas.
Isso não é capricho: é o que o Genie lê no prompt 6 para escolher a coluna
certa. Coluna sem comentário é coluna que ele usa errado, com confiança.

08-testes.sql — os 9 testes, cada um levantando exceção com raise_error()
quando falhar, para o job PARAR:
  1. receita da gold = receita da silver = R$ 102.303.828,05 (tolerância 0,01)
     Esse é o teste que mais importa: limpeza NÃO PODE mudar o faturamento.
  2. CNPJ único na silver.clientes (0 duplicados)
  3. nenhuma data_pedido nula na silver.pedidos
  4. receita negativa só onde devolucao = true
  5. volume da gold.fato_vendas entre 140.000 e 250.000 linhas
  6. nenhum pedido_id na gold que não exista na silver.pedidos
  7. nenhum cliente_id na gold que não exista na silver.clientes
  8. mart_produto_performance soma o mesmo que fato_vendas
  9. todo CNPJ com exatamente 14 dígitos
  Cada teste imprime nome, valor calculado, valor esperado e passou/falhou.

Acrescente ao resources/pipeline.job.yml:
  gold_dimensoes   depends_on: as quatro tarefas silver
  gold_fato_vendas depends_on: gold_dimensoes
  gold_marts       depends_on: gold_fato_vendas
  testes           depends_on: gold_marts   ← por último, e obrigatório

Rode e me mostre a saída:
  databricks bundle deploy --target dev --profile <PERFIL>
  databricks bundle run rotaperfume_pipeline --target dev --profile <PERFIL>

Os 9 testes precisam passar. Se algum falhar, corrija a transformação —
nunca o teste.
```

---

## Como verificar a feature

**1 · A mesma pergunta do "o que mostrar antes", agora em uma linha**

```sql
SELECT marca, ROUND(SUM(receita)/1e6, 1) AS receita_mi
FROM lakehouse_rotaperfume.gold.fato_vendas
GROUP BY marca ORDER BY 2 DESC LIMIT 5;
-- Layali 18,6 · ... · Attar Real 5,2
```

Sem `JOIN`, sem `CAST`, sem lembrar do `WHERE NOT cancelado` — o filtro já está
dentro do contrato do fato. Compare com o `exemplo-06` de ontem, que precisou de
três `JOIN` e dois `CAST` para chegar no mesmo número.

**2 · O grão é o que o contrato diz que é: uma linha por item de pedido**

```sql
SELECT
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.silver.itens_pedido)          AS itens_na_silver,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.gold.fato_vendas)             AS linhas_no_fato,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.silver.pedidos WHERE cancelado) AS pedidos_cancelados;
-- 197.724 · 191.080 · 957
```

A diferença — 6.644 linhas — são exatamente os itens dos 957 pedidos
cancelados, cerca de sete itens por pedido. **Se o fato tivesse MAIS linhas que
a silver, algum `JOIN` duplicou linha**, e é o erro mais comum de quem monta
fato pela primeira vez:

```sql
SELECT ROUND(COUNT(*) / COUNT(DISTINCT pedido_id), 1) AS itens_por_pedido
FROM lakehouse_rotaperfume.gold.fato_vendas;   -- ~6,9. Se der 13,8, dobrou.
```

**3 · Conformado significa que os três marts somam igual**

```sql
SELECT
  (SELECT ROUND(SUM(valor_liquido),2) FROM lakehouse_rotaperfume.silver.pedidos)                   AS silver,
  (SELECT ROUND(SUM(receita),2)       FROM lakehouse_rotaperfume.gold.fato_vendas)                 AS fato,
  (SELECT ROUND(SUM(receita),2)       FROM lakehouse_rotaperfume.gold.mart_vendas_por_vendedor)    AS mart_comercial,
  (SELECT ROUND(SUM(receita),2)       FROM lakehouse_rotaperfume.gold.mart_produto_performance)    AS mart_produto;
-- as quatro colunas: R$ 102.303.828,05
```

> *"Quatro tabelas diferentes, quatro consumidores diferentes, o mesmo número.
> É isso que a palavra 'conformado' significa — e é o teste 8."*

### O que tem que aparecer na tela — com a query de cada número

| Número | Valor | Query |
|---|---|---|
| Linhas na `fato_vendas` | **191.080** | `SELECT COUNT(*) FROM gold.fato_vendas` |
| Receita (com devolução) | **R$ 102.303.828,05** | `SELECT ROUND(SUM(receita),2) FROM gold.fato_vendas` |
| Bruto vendido | **R$ 103.568.586,35** | `SELECT ROUND(SUM(receita) FILTER (WHERE NOT devolucao),2) FROM gold.fato_vendas` |
| Diferença entre os dois | **R$ 1,26 mi** — a devolução | `SELECT ROUND(SUM(receita) FILTER (WHERE devolucao),2) FROM gold.fato_vendas` |
| Margem total | **R$ 41.125.619,86 (40,2%)** | `SELECT ROUND(SUM(margem),2), ROUND(100*SUM(margem)/SUM(receita),1) FROM gold.fato_vendas` |
| Layali, a marca líder | **R$ 18,4 mi líquido · R$ 18,6 mi bruto** | ver query (b) abaixo |
| Kit Presente | margem **33,0%** — a pior | ver query (c) abaixo |
| Óleo Concentrado | margem **49,9%** — a melhor | ver query (c) abaixo |
| Outubro/2025 · Janeiro/2026 | **R$ 7,02 mi · R$ 2,46 mi** | ver query (d) abaixo |

```sql
-- (a) os quatro primeiros números de uma vez
SELECT
  COUNT(*)                                                    AS linhas,
  ROUND(SUM(receita), 2)                                      AS receita_liquida,
  ROUND(SUM(receita) FILTER (WHERE NOT devolucao), 2)         AS bruto_vendido,
  ROUND(SUM(receita) FILTER (WHERE devolucao), 2)             AS devolucoes,
  ROUND(SUM(margem), 2)                                       AS margem,
  ROUND(100 * SUM(margem) / SUM(receita), 1)                  AS margem_pct
FROM lakehouse_rotaperfume.gold.fato_vendas;
```

```sql
-- (b) a marca líder, líquido e bruto lado a lado
SELECT marca,
       ROUND(SUM(receita)/1e6, 1)                             AS liquido_mi,
       ROUND(SUM(receita) FILTER (WHERE NOT devolucao)/1e6, 1) AS bruto_mi
FROM lakehouse_rotaperfume.gold.fato_vendas
GROUP BY marca ORDER BY liquido_mi DESC LIMIT 3;
-- Layali: 18,4 líquido · 18,6 bruto
```

```sql
-- (c) a melhor e a pior categoria por margem — o gráfico do prompt 5
SELECT categoria,
       ROUND(SUM(receita)/1e6, 1)                 AS receita_mi,
       ROUND(100 * SUM(margem) / SUM(receita), 1) AS margem_pct
FROM lakehouse_rotaperfume.gold.fato_vendas
GROUP BY categoria ORDER BY margem_pct;
-- Kit Presente 33,0 na ponta de baixo · Óleo Concentrado 49,9 na de cima
```

```sql
-- (d) o pico e o vale — a sazonalidade invertida do setor
SELECT ano, mes, ROUND(SUM(receita)/1e6, 2) AS receita_mi
FROM lakehouse_rotaperfume.gold.fato_vendas
WHERE (ano = 2025 AND mes = 10) OR (ano = 2026 AND mes = 1)
GROUP BY ano, mes ORDER BY ano, mes;
-- outubro/2025: 7,02   ·   janeiro/2026: 2,46
```

**4 · A prova de que os testes têm dente — quebre um de propósito**

```sql
-- o mecanismo, isolado: raise_error dentro de CASE WHEN interrompe a tarefa
SELECT CASE WHEN 1 = 1 THEN 'PASSOU'
            ELSE raise_error('receita da gold diferente da silver') END AS teste_1;
-- troque 1 = 1 por 1 = 0 e rode de novo:
-- [USER_RAISED_EXCEPTION] receita da gold diferente da silver
```

Para ver a falha **de verdade**, sem mexer no teste (o que a gente nunca faz):
corrompa a gold e rode **só** a tarefa `testes`.

```sql
DELETE FROM lakehouse_rotaperfume.gold.fato_vendas WHERE ano = 2026 AND mes = 1;
-- 7.700 linhas a menos; a receita cai para R$ 99.839.788,76
```

```bash
# o job_id vai DENTRO do JSON: com --json a CLI não aceita argumento posicional
databricks jobs run-now --profile <PERFIL> \
  --json '{"job_id":<job_id>,"only":["testes"]}'
# [USER_RAISED_EXCEPTION] receita da gold (99839788.76)
#                         diferente da silver (102303828.05)
```

Mostre o DAG: `testes` em vermelho e as outras nove tarefas em `DISABLED`.
Depois rode o job inteiro para restaurar — ele reconstrói o fato e volta ao verde.

> **Por que `--only` e não o job inteiro:** rodando tudo, `gold_fato_vendas`
> reconstrói o fato antes de `testes` rodar, e o teste passa. O `--only` é o que
> reproduz o caso real — alguém mexeu na tabela depois que o pipeline rodou.

> *"O dashboard vai ficar com o dado de ontem. É de longe o melhor dos dois
> cenários ruins — o outro é ele ficar com o dado errado de hoje, e ninguém
> perceber até a reunião de segunda."*

---

## Fala de aula

> *"Ontem eu levei quinze minutos escrevendo query para chegar nesse número.
> Agora é `SELECT marca, SUM(receita)` — cinco segundos. E, mais importante:
> sai igual para todo mundo da empresa, para sempre, porque a regra de margem
> está escrita numa tabela e não na cabeça de quem escreveu a query.*
>
> *E olha o último bloco: nove testes. O primeiro é o que mais importa — a
> receita da gold tem que ser exatamente a da silver. Se um dia alguém mexer
> numa transformação e o número mudar, o job **quebra**, e o dashboard fica com
> o dado de ontem. Que é infinitamente melhor do que ficar com o dado errado
> de hoje."*


---

## Se der errado ao vivo

| Sintoma | Causa | Correção em um prompt |
|---|---|---|
| A gold soma R$ 103,6 mi e a silver R$ 102,3 mi | A devolução ficou de fora do fato | *"Traga a devolução para dentro do fato, com valor negativo e flag."* |
| `raise_error` reclama de tipo | Ele retorna tipo `NOTHING` | Use dentro de `CASE WHEN ... THEN 'PASSOU' ELSE raise_error(...) END` |
| O fato tem mais linhas que o esperado | Faltou excluir pedido cancelado | `WHERE NOT p.cancelado` |
| Um teste falhou | **Ótimo. É para isso que ele existe.** | Corrija a transformação, **nunca** o teste |
| O job inteiro fica verde mesmo com a gold corrompida | `gold_fato_vendas` reconstrói o fato antes de `testes` rodar | Use `--only testes` para reproduzir o caso real |
| A execução demora bem mais que o medido | Warehouse e compute serverless dormiram | Rode um `SELECT 1` para acordar antes de medir |

**Tempo medido:** ~8s de deploy, ~4min50 do pipeline inteiro com as 10 tarefas,
com o warehouse já quente.