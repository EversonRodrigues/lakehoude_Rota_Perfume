# Prompt 3 · A fila e o agente

**Slides que acompanham:** 38 a 45 (divisor *"Os 200"*, batch ou tempo real, o
gap que mata projetos, as ferramentas do agente, a resposta para o diretor, o
antes e o depois, o arco de três noites, a frase da noite).

**Entrega:** `gold.fila_semanal` — as 200 linhas com nome, motivo em português
e o que oferecer — mais as quatro ferramentas que o agente consulta.
**Deploy nº 3 da noite.**

> Score não é decisão. `0,8412` não é uma ação. Este prompt é o último metro:
> o que separa o modelo que roda do modelo que alguém usa.

---

## O ambiente, conferido hoje

Rodado contra `lakehouse_rotaperfume` no workspace. **Tudo o que este prompt
usa já existe** — nenhuma fonte precisa ser criada antes:

| Tabela | O que este prompt lê dela |
|---|---|
| `gold.score_propensao` | criada no prompt 2 — 2.810 clientes com nota |
| `gold.features_cliente` | as features, para escrever o motivo |
| `gold.dim_cliente` | `razao_social`, `cidade`, `uf` |
| `silver.carteira` | `vigente` e `orfao_vendedor_desligado` — os dois são filtro |
| `silver.vendedores` | `nome` e `ativo`. A carteira só tem `vendedor_id` |
| `silver.estoque` | snapshot semanal: `data_snapshot`, `saldo`, `ruptura` |

Não há nenhuma função SQL em `gold` — as quatro ferramentas nascem aqui.

O job está com **12 tarefas** e o `bundle deploy` passa limpo.

> **No deploy, se aparecer pedido de confirmação para APAGAR O DASHBOARD:
> recuse e me chame.** O dashboard é da noite 2 e a chave do recurso
> (`dashboard_comercial`) não pode ser renomeada — trocar a chave faz o bundle
> apagar e recriar, com URL nova. **Nunca use `--auto-approve` aqui.**

---

## O que mostrar antes

**1 · O score, cru, como ele sai do modelo**

```sql
SELECT cliente_id, ROUND(score, 4) AS score, faixa
FROM lakehouse_rotaperfume.gold.score_propensao
ORDER BY score DESC LIMIT 5;
```

> *"Está certíssimo e é inútil. Entregue isso para o vendedor e ele volta a
> ligar pela intuição na segunda-feira. Já vi acontecer com modelo de AUC 0,89
> rodando há dois anos."*

**2 · A pergunta que decide o desenho da tabela**

Faça para a sala antes de colar o prompt:

> *"São 200 ligações e 42 vendedores. Dou 5 para cada um, ou dou os 200
> melhores da base inteira?"*

A resposta quase sempre é "5 para cada, é mais justo". E aí:

> *"Justo com quem? Se a carteira do João está quente e a do Pedro está fria,
> a cota igual obriga o João a deixar cliente quente na mesa para o Pedro
> ligar para cliente frio."*

**A fila é global; a capacidade é que é por pessoa.** É por isso que a tabela
sai com `ORDER BY score DESC LIMIT 200` e não com cota por vendedor.

---

**Enquanto ele trabalha, você explica:**

- **O último metro é onde os projetos morrem.** Dado, modelo, score na
  tabela — e ninguém liga. O gargalo nunca é o algoritmo.
- **Motivo em português não é enfeite.** É o que faz o vendedor confiar
  quando o modelo acerta, e o que permite entender **por que** quando ele
  erra, em vez de simplesmente parar de usar.
- **Agente não inventa: ele consulta.** As quatro ferramentas são consultas ao
  Unity Catalog, com nome e contrato. Agente sem dado organizado por trás é
  chute com sotaque — e as três noites anteriores foram construir esse dado.
- **A carteira entra aqui.** O score é por cliente; a ligação é por vendedor.
  `silver.carteira` é quem faz a ponte, e é por isso que ela foi limpa na
  noite 2.

---

## O prompt

```
Continue o mesmo bundle. gold.score_propensao tem os 3.000 clientes com nota.

Crie src/ml/13-fila.sql — um arquivo SQL para rodar como sql_task.

1. A TABELA DA SEMANA: gold.fila_semanal

   As fontes e como juntar:
     gold.score_propensao   cliente_id, score, faixa, versao
     gold.features_cliente  as features, para escrever o motivo
     gold.dim_cliente       razao_social, cidade, uf
     silver.carteira        cliente_id -> vendedor_id.
                            FILTRE por vigente = true, e descarte
                            orfao_vendedor_desligado = true: vendedor
                            desligado não recebe ligação para fazer.
     silver.vendedores      vendedor_id -> nome. A carteira só tem o id.

   A ORDEM DAS OPERAÇÕES IMPORTA, e é o erro mais fácil de cometer aqui:

     1º  junte a carteira e DESCARTE quem não é elegível
         (sem carteira vigente, ou vendedor desligado)
     2º  ORDER BY score DESC LIMIT 200
     3º  ROW_NUMBER() OVER (PARTITION BY vendedor ORDER BY score DESC)

   Se o descarte vier DEPOIS do LIMIT, a fila sai com ~172 linhas em vez de
   200 — seis dos 42 vendedores estão desligados e levam junto os clientes
   deles — e o teste 1 quebra o job. Filtrando antes, sobram 2.393 clientes
   elegíveis e a fila fecha em 200 exatas, distribuídas em ~36 vendedores.
   Não use cota igual por vendedor: a carteira de um é mais quente que a do
   outro, e cota fixa obriga a gastar ligação com cliente frio.

   Colunas: vendedor, ordem, cliente_id, razao_social, cidade, uf, score,
   faixa, ticket_medio, e duas colunas escritas para gente ler:

   motivo — uma frase em português montada com CASE WHEN sobre as features,
   com os números reais do cliente dentro, via FORMAT_NUMBER:
     atraso_relativo > 3   -> 'Compra a cada N dias e está há M sem pedido.
                               Risco de perder para o concorrente.'
     atraso_relativo > 1.5 -> 'Está N vezes mais atrasado que o ritmo dele.'
     comprou_lancamento    -> 'Comprou lançamento recente. Alta chance de
                               repetir.'
     valor_total no topo   -> 'Cliente grande, R$ X no ano. Manter próximo.'
     ELSE                  -> 'Dentro do ritmo. Contato de manutenção.'
   O ELSE é obrigatório: motivo nulo quebra o teste 2.

   sugestao — o SKU mais comprado pelo cliente na marca preferida dele que
   ele NÃO comprou nos últimos 90 dias, com o saldo vindo do snapshot mais
   recente de silver.estoque (a tabela é um snapshot semanal: pegue
   max(data_snapshot) por sku, não a tabela inteira).

2. AS QUATRO FERRAMENTAS, como funções SQL no Unity Catalog, cada uma com
   COMMENT em português dizendo para que serve — é o COMMENT que o agente lê:

   gold.priorizar_carteira(p_vendedor STRING, p_quantos INT)
     RETURNS TABLE — a fatia da fila_semanal daquele vendedor, em ordem
   gold.contexto_cliente(p_cliente_id INT)
     RETURNS TABLE — histórico, ticket médio, marcas preferidas, última compra
   gold.sugerir_produtos(p_cliente_id INT)
     RETURNS TABLE — o que ele compra e parou de comprar nos últimos 90 dias
   gold.checar_disponibilidade(p_sku STRING)
     RETURNS TABLE — saldo e ruptura no snapshot mais recente

   Prefixe TODO parâmetro com p_: parâmetro com o mesmo nome de uma coluna
   fica ambíguo dentro do corpo da função e o CREATE falha.
   cliente_id é INT no catálogo, não BIGINT.

3. TRÊS TESTES QUE QUEBRAM O JOB, no mesmo padrão raise_error() dentro de
   CASE WHEN que a noite 2 usa:
   - a fila tem exatamente 200 linhas
   - nenhuma linha com motivo nulo ou vazio
   - nenhum score fora do intervalo [0, 1]

4. CRIE o Genie Space (ele NÃO existe ainda neste repositório) com
   gold.fila_semanal, gold.score_propensao e gold.dim_cliente, e a instrução:
   "Use sempre as tabelas e funções deste espaço. Nunca invente número,
    nome de cliente ou quantidade de estoque."

   ATENÇÃO: Genie NÃO é um tipo de recurso do DABs — não dá para declarar no
   bundle como o dashboard. Ele nasce por CLI:
     databricks workspace mkdirs /Users/<voce>/genie
     databricks genie create-space --json @payload.json
   O campo serialized_space tem formato próprio: todo item de
   sample_questions, example_question_sqls e text_instructions precisa de um id
   de 32 hex, os campos de texto são ARRAYS de string, e text_instructions
   aceita no máximo UM item. Versione o JSON no repo mesmo assim
   (resources/genie-comercial.json) — é o mais perto de "como código" que dá.

Tabelas, colunas e funções com COMMENT em português.

Registre a tarefa ml_fila em resources/pipeline.job.yml, depois de ml_modelo,
e faça o deploy.
```

---

## Como verificar a feature

**1 · A resposta para o diretor, na tela**

```sql
SELECT vendedor, ordem, razao_social, ROUND(score, 2) AS score, motivo
FROM lakehouse_rotaperfume.gold.fila_semanal
WHERE vendedor = (SELECT vendedor FROM lakehouse_rotaperfume.gold.fila_semanal
                  GROUP BY vendedor ORDER BY COUNT(*) DESC LIMIT 1)
ORDER BY ordem;
```

A lista de quem recebeu mais contatos, com nome e motivo. **É o slide *A resposta para o diretor* saindo do banco.** Leia a
primeira em voz alta e pare.

**2 · A conta fecha, e a distribuição conta uma história**

```sql
SELECT COUNT(DISTINCT vendedor) AS vendedores,
       COUNT(*)                 AS ligacoes
FROM lakehouse_rotaperfume.gold.fila_semanal;

-- quem recebeu muito e quem recebeu pouco
SELECT vendedor, COUNT(*) AS ligacoes, ROUND(AVG(score), 3) AS score_medio
FROM lakehouse_rotaperfume.gold.fila_semanal
GROUP BY vendedor ORDER BY ligacoes DESC;
```

**200 contatos em 36 vendedores, de 1 a 11 ligações cada** — medido. São 36 e
não 42 porque seis vendedores estão desligados com carteira ainda vinculada — a
nona das dez sujeiras da noite 2, aparecendo de novo.

> **E uma décima sujeira aparece só aqui:** `COUNT(DISTINCT vendedor)` dá **35**,
> não 36. São **dois pares de homônimos** — `Henrique Oliveira` (ids 34 e 36) e
> `Vinícius Lopes` (31 e 37). Agrupar a fila pelo nome funde a carteira de duas
> pessoas numa lista só. Por isso a tabela tem `vendedor_id` e o `ROW_NUMBER()`
> particiona por ele. Rode as duas contagens lado a lado na aula: é o argumento
> mais barato que existe para "chave é id, não nome". O vendedor do topo não é o
melhor vendedor — é o que tem a carteira mais quente. E isso é uma
conversa de negócio que só existe porque agora tem número.

**3 · A ferramenta, chamada como o agente chamaria**

```sql
SELECT * FROM lakehouse_rotaperfume.gold.priorizar_carteira('Ana Souza', 5);
```

> *"Isso não é um endpoint, não é um framework e não tem prompt nenhum. É uma
> função no catálogo, com contrato e comentário. O agente só sabe chamar."*

**4 · O Genie, que é a interface**

Abra o Genie Space e pergunte, com as palavras do vendedor:

> *"Quem eu ligo essa semana?"*

Depois peça o que só o dado responde:

> *"Por que a Perfumaria Aurora está no topo da minha lista?"*

**Mostre o SQL que o Genie gerou.** É a diferença entre agente e chute: a
resposta tem query embaixo.

---

## Se der errado

| Sintoma | Causa | Saída |
|---|---|---|
| `CREATE FUNCTION` falha com coluna ambígua | parâmetro com o mesmo nome de uma coluna | prefixe com `p_` — está no prompt, mas acontece |
| `INVALID_LIMIT_LIKE_EXPRESSION.IS_UNFOLDABLE` | `LIMIT p_quantos` dentro da função: a expressão do `LIMIT` tem que ser **constante**, e parâmetro não é | troque por `WHERE ordem <= p_quantos` — `ordem` já é o ranking dentro da carteira, então dá no mesmo e fica mais legível |
| `CREATE FUNCTION ... RETURNS TABLE` recusado | função de tabela indisponível no workspace | plano B: crie as quatro como **views** (`gold.ferramenta_*`) e mostre o Genie consultando; o argumento da aula é o mesmo |
| A fila veio com ~165 linhas | o descarte de vendedor desligado rodou DEPOIS do `LIMIT 200` | é o erro previsto no prompt: peça para filtrar antes de limitar. **Mostre a sujeira nº 9 da noite 2 cobrando o preço dela** |
| A fila fecha em **35** vendedores, não 36 | `ROW_NUMBER()` particionado pelo **nome** do vendedor | **há homônimos na base**: dois `Henrique Oliveira` (ids 34 e 36) e dois `Vinícius Lopes` (31 e 37). Particione por `vendedor_id` — pelo nome, duas carteiras viram uma fila só e nenhum dos dois sabe quais ligações são dele. Uma sujeira que só aparece aqui, no último metro |
| `motivo` com `NULL` no meio | faltou o `ELSE` no `CASE WHEN` | o teste 2 pegou. É o teste funcionando |
| O Genie inventou um número | a instrução não entrou no espaço | mostre o antes e o depois da instrução — vale mais que dez slides sobre alucinação |
| `Invalid serialized_space: Unknown field` | o payload do Genie tem schema próprio | chaves de topo: `version`, `config`, `data_sources`, `instructions`. Ids de 32 hex, textos em array, **um** `text_instructions` |
| `Tree node with path ... does not exist` | o `parent_path` do Genie precisa existir antes | `databricks workspace mkdirs` primeiro |
| No Git Bash, o caminho do workspace vira `C:/Program Files/Git/...` | o Git Bash traduz caminhos que começam com `/` | rode os comandos de workspace/Genie pelo **PowerShell** |
| 85% dos `motivo` com a mesma frase | `comprou_lancamento` é verdadeiro em 71% da base e estava cedo demais no `CASE` | desça-o para depois dos sinais específicos. Motivo que se repete em 170 de 200 linhas não explica nada |