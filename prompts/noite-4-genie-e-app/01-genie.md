# Prompt 1 · O Genie da direção

> **Antes de colar:** troque `<PERFIL>`, `<WAREHOUSE_ID>` e `<HOST_DO_WORKSPACE>`
> pelos valores do seu ambiente — a tabela está em
> [prompts/README.md](../README.md#as-variáveis).


**Slides que acompanham:** 19 a 24 (divisor *"A porta que já existia"*, um Genie
por audiência, o que é instrução de negócio, a tabela que nasce vazia).

**Entrega:** o space `Rota Perfume · Direção` como código no bundle, mais
`gold.retorno_ligacao` e a tarefa que a cria. **Deploy nº 1 da noite.**

> O Genie da noite 2 serve para perguntar qualquer coisa. Este serve para
> responder **uma decisão**. A diferença não é técnica — é de audiência, e é o
> argumento do prompt.

---

## O ambiente, conferido hoje

Rodado contra `lakehouse_rotaperfume` no workspace `<HOST_DO_WORKSPACE>`, profile
`<PERFIL>`, warehouse `<WAREHOUSE_ID>`. **Tudo o que este prompt lê já
existe:**

| Fonte | O que este prompt faz com ela |
|---|---|
| `gold.fila_semanal` | 200 linhas, 36 vendedores — é o assunto principal do space |
| `gold.score_propensao` | a nota de **todos** os clientes, não só dos 200 |
| `gold.modelo_metricas` | a última versão tem `lift_top200` = **4,15** e `acertos_top200` = **84** |
| `gold.dim_cliente` | achar pela razão social o cliente que não está na fila |

O que **não** existe ainda: `gold.retorno_ligacao` e o segundo Genie space.
Ambos nascem aqui.

O job está com **13 tarefas** e o `bundle deploy` passa limpo. Ele termina a
noite com **15**.

> **Divergência com o material original, de propósito.** O roteiro do curso
> pede sete fontes, incluindo `clientes_em_risco`, `ranking_marcas` e
> `receita_mensal`. **Essas três views não existem neste workspace** — são de um
> ambiente de aula que tinha um backlog de views de negócio que este repositório
> nunca construiu. O space aqui nasce com **cinco** fontes reais. O argumento da
> noite ("um Genie por audiência") não depende da contagem.

> **No deploy, se aparecer pedido de confirmação para APAGAR o dashboard:
> recuse e me chame.** A chave do recurso (`comercial`, em
> `resources/dashboard.dashboard.yml`) não pode ser renomeada — trocar a chave
> faz o bundle apagar e recriar, com URL nova. O mesmo vale, a partir de hoje,
> para a chave `genie_direcao`. **Nunca use `--auto-approve` aqui.**
>
> O Genie **comercial** da noite 2 não corre esse risco: ele não é recurso do
> bundle, foi criado pela CLI e o payload dele mora em
> `resources/genie-comercial.json`.

---

## O que mostrar antes

**1 · O Genie que já existe, com a pergunta do diretor**

Abra o `Rota Perfume - Comercial` da noite 2 e pergunte:

> *"Quem eu ligo essa semana?"*

Ele responde — a fila entrou nas fontes dele na noite 3. Guarde a resposta.

**2 · E agora a pergunta que expõe o problema**

> *"Quantas dessas ligações viraram pedido?"*

Ele **não tem como saber**. A informação não existe em lugar nenhum do projeto:
o pipeline sabe a quem ligar e nunca fica sabendo o que aconteceu depois.

```sql
-- procure a tabela que responderia. Ela não está aqui.
SHOW TABLES IN lakehouse_rotaperfume.gold;
```

> *"Três noites construindo o caminho de ida. Hoje a gente constrói o de volta —
> e ele começa com uma tabela vazia."*

**3 · A pergunta de desenho, para a sala**

> *"Eu já tenho um Genie. Por que eu criaria um segundo, com o mesmo dado
> embaixo?"*

A resposta que quase sempre aparece é "não criaria". E aí:

> *"O vendedor pergunta 'quanto o cliente X comprou no ano'. O diretor pergunta
> 'quanto vale a fila'. Se os dois moram no mesmo espaço, as instruções brigam:
> o que serve para um vira ruído para o outro. **Genie não é um por empresa. É
> um por audiência.**"*

---

**Enquanto ele trabalha, você explica:**

- **A instrução é o produto.** O modelo é o mesmo, o dado é o mesmo. O que faz
  este Genie responder melhor que o outro para o diretor são doze linhas de
  texto escritas por alguém que entende o negócio — e elas moram no Git, com
  revisão e histórico.
- **"Nunca cite AUC" é uma regra de negócio.** Não é preciosismo: quem pergunta
  aqui decide ligação, não modelo. A métrica dele é `lift_top200`. E a regra tem
  que ser literal, porque `modelo_metricas` expõe **cinco** colunas de AUC —
  elas estão ali para quem treina, e é justamente por estarem ali que a
  instrução precisa proibi-las pelo nome.
- **A tabela que nasce vazia.** `retorno_ligacao` é a única tabela do projeto
  cujo dado não vem do pipeline — vem do time. Por isso ela é a única com
  `CREATE TABLE IF NOT EXISTS`: um redeploy não pode apagar o que o vendedor
  respondeu.
- **Resposta vazia é resposta certa.** O Genie precisa ser instruído a dizer
  "ninguém registrou retorno ainda" em vez de inventar um número ou usar a fila
  como se fosse retorno.
- **Metadado vira tarefa hoje.** A regra "toda coluna da gold tem COMMENT"
  existia como combinado desde a noite 2 e nunca foi verificada por ninguém.
  Resultado: **65 colunas sem COMMENT**. Combinado que ninguém verifica não é
  regra, é intenção — por isso ela vira uma tarefa que quebra o job.

---

## O prompt

```
Continue o bundle em rotaperfumes/.
A noite 3 deixou gold.fila_semanal com 200 contatos e gold.score_propensao
com a nota de todos os clientes. Hoje eu quero três coisas: a tabela onde o
time registra o que aconteceu depois da ligação, a tarefa que garante que
metadado não falte, e um Genie space feito para a direção.

1. src/gold/12-retorno-ligacao.sql — a tabela do caminho de volta

   CREATE TABLE IF NOT EXISTS lakehouse_rotaperfume.gold.retorno_ligacao com:
     cliente_id      INT
     vendedor        STRING
     status          STRING     vendeu | vai_pensar | sem_interesse | nao_atendeu
     comentario      STRING     texto livre do vendedor
     registrado_em   TIMESTAMP
     registrado_por  STRING     e-mail de quem estava logado
     _referencia     DATE       a semana da fila

   IF NOT EXISTS, e não CREATE OR REPLACE: é a ÚNICA tabela do projeto cujo
   dado não vem do pipeline. Um redeploy não pode apagar o que o time
   respondeu.

   COMMENT em toda coluna e na tabela. Como aqui NÃO é CTAS, o COMMENT de
   coluna cabe inline na lista de colunas.

   No COMMENT de `vendedor`, registre o problema real: nome de vendedor não é
   único nesta base, então a coluna serve para exibir, nunca para agrupar.

   Acrescente ao pipeline a tarefa gold_retorno_ligacao, com depends_on em
   gold_marts — e não no bloco de ML. O app da noite precisa da tabela mesmo
   num dia em que o modelo falhe.

2. src/gold/13-auditoria-metadado.sql — a regra que vira tarefa

   Varra o information_schema e levante raise_error se qualquer TABELA ou
   COLUNA do schema gold estiver sem COMMENT. A mensagem tem que NOMEAR
   tabela.coluna — auditoria que só diz "faltam 7" devolve o trabalho para
   quem lê o log.

   raise_error() retorna o tipo NOTHING e não pode ficar solto num SELECT:
   use CASE WHEN <condição boa> THEN 'PASSOU' ELSE raise_error(...) END,
   como em src/gold/08-testes.sql.

   Tarefa auditoria_de_metadado, a ÚLTIMA do job (depends_on ml_fila e
   gold_retorno_ligacao) — só assim ela enxerga fila_semanal e retorno_ligacao.

   ANTES de ligar isso: hoje a gold tem 65 colunas sem COMMENT. Preencha
   todas, em 05-dimensoes.sql, 06-fato-vendas.sql, 07-marts.sql e
   11-fila.sql, com ALTER TABLE ... ALTER COLUMN ... COMMENT no fim do arquivo
   que cria a tabela (CTAS não aceita COMMENT de coluna inline, e apaga os
   existentes a cada run — é por isso que os ALTER moram no mesmo arquivo).
   Escreva comentário de NEGÓCIO, não paráfrase do nome da coluna.

   Escopo: só gold. Silver (97 colunas) e bronze (106) ficam de fora —
   bronze é o dado como chegou, e silver é a próxima dívida.

   O job vai de 13 para 15 tarefas.

3. resources/direcao.geniespace.json + resources/genie-direcao.genie_space.yml

   Um SEGUNDO Genie space, chamado "Rota Perfume · Direção", como RECURSO DO
   BUNDLE — genie_spaces é tipo de recurso do DABs a partir da CLI v1.14.0.
   Chave do recurso: genie_direcao. Não altere o genie comercial, que não é
   recurso do bundle.

   Fontes, e só estas cinco:
     gold.fila_semanal      o assunto principal
     gold.score_propensao   a nota de todos, para o cliente fora da fila
     gold.modelo_metricas   lift_top200, acertos_top200, taxa_base
     gold.retorno_ligacao   o que aconteceu depois
     gold.dim_cliente       achar pela razão social quem não está na fila

   As instruções, em português, cobrindo:
   - quem pergunta: a direção comercial, que não escreve SQL e decide ligação
   - o que é score (0 a 1, chance de comprar em 7 dias), faixa, ordem, motivo
   - por que a fila é GLOBAL e não cota por vendedor: quem tem carteira quente
     recebe mais contatos, e isso está certo
   - receita esperada da fila = SUM(score * ticket_medio), e é ESTIMATIVA,
     nunca receita realizada
   - a métrica da direção é lift_top200. NUNCA cite AUC para responder
     pergunta de negócio, e proíba pelo NOME as cinco colunas de AUC
   - modelo_metricas tem uma linha por treino: use sempre a versão mais recente
   - retorno_ligacao começa VAZIA. Se a resposta for zero, diga que ninguém
     registrou retorno ainda — não invente número, e não use a fila como se
     fosse retorno
   - um cliente pode ter mais de um retorno: para o estado atual, use o mais
     recente por registrado_em
   - nunca agrupe métrica por NOME de vendedor
   - a sazonalidade é INVERTIDA: o pico é o mês ANTERIOR à data comemorativa
   - nunca use o schema bronze

   5 sample_questions e 5 pares pergunta -> SQL já validado, incluindo
   "Quem eu ligo essa semana?", "Quanto vale a fila desta semana?" e
   "Quantas ligações já foram registradas e quantas viraram pedido?".

   AS QUATRO REGRAS DA API QUE FAZEM O DEPLOY FALHAR:
   a) data_sources.tables ORDENADO por identifier
   b) column_configs de cada tabela ordenado por column_name
   c) todo id com 32 caracteres hexadecimais minúsculos, sem hífen, e ÚNICO
      entre as três listas somadas
   d) as listas de perguntas e instruções também ordenadas por id
   e) text_instructions aceita NO MÁXIMO UM item — junte tudo no content

   Gere os ids com md5 do conteúdo — determinístico. Um redeploy não pode
   recriar as perguntas nem sujar o diff do Git.

   parent_path é imutável e a pasta precisa existir ANTES do primeiro deploy:
   databricks workspace mkdirs /Workspace/Users/<você>/genie

4. scripts/rodar-tarefa.ps1 — rodar UMA tarefa do job

   PowerShell, no padrão dos scripts existentes: profile como 1º parâmetro
   posicional, e nunca um parâmetro chamado $Profile (colide com a variável
   automática do PowerShell). Lê o job_id do `bundle summary` e dispara
   `databricks jobs run-now --json` com {"only":["<tarefa>"]}.

5. Rode, e me mostre o resultado:
   databricks bundle validate --strict --target dev --profile <PERFIL>
   databricks bundle deploy            --target dev --profile <PERFIL>
   databricks bundle run rotaperfume_pipeline --target dev --profile <PERFIL>

   NÃO use --auto-approve. Se o deploy pedir para apagar o dashboard, pare e
   me avise.
```

---

## Como verificar a feature

**1 · A tabela existe, está vazia e tem metadado**

```sql
DESCRIBE TABLE EXTENDED lakehouse_rotaperfume.gold.retorno_ligacao;

-- tem que voltar 0. Vazia no começo da noite é o estado correto.
SELECT COUNT(*) AS linhas FROM lakehouse_rotaperfume.gold.retorno_ligacao;
```

**2 · A gold inteira tem metadado — não só a tabela nova**

```sql
-- tem que voltar VAZIO nos dois casos
SELECT table_name, column_name
FROM   lakehouse_rotaperfume.information_schema.columns
WHERE  table_schema = 'gold' AND (comment IS NULL OR trim(comment) = '');

SELECT table_name
FROM   lakehouse_rotaperfume.information_schema.tables
WHERE  table_schema = 'gold' AND (comment IS NULL OR trim(comment) = '');
```

**3 · Os invariantes das três noites anteriores não se mexeram**

```sql
SELECT ROUND(SUM(receita), 2) FROM lakehouse_rotaperfume.gold.fato_vendas;
-- 102303828.05 — o número que sobrevive a toda camada, desde a noite 2

SELECT COUNT(*) FROM lakehouse_rotaperfume.gold.fila_semanal;   -- 200
```

**4 · O segundo space existe, e o primeiro continua de pé**

```bash
databricks genie list-spaces --profile <PERFIL>
# tem que listar os DOIS: "Rota Perfume - Comercial" e "Rota Perfume · Direção"

databricks bundle summary --target dev --profile <PERFIL>
# o id do genie_direcao sai daqui — o prompt 2 vai precisar dele. NÃO invente.
```

**5 · As três perguntas no Genie novo — e é aqui que a sala vê a diferença**

Abra o `Rota Perfume · Direção` e pergunte, nesta ordem:

| Pergunta | O que tem que aparecer |
|---|---|
| *"Quanto vale a fila desta semana?"* | **R$ 556.423,71** e a palavra *estimativa* |
| *"Quantas ligações já foram registradas?"* | **zero** — e a frase de que ninguém registrou ainda |
| *"O modelo é bom?"* | **4,15×** e **84 de 200**. **Não pode citar AUC** |

Medido neste workspace, as três passam. A segunda responde literalmente
*"0. Ninguem registrou retorno de ligacao ainda."* — e a terceira fala em
lift e acertos sem tocar no AUC, que está a uma coluna de distância.

Confira o primeiro contra a query, na frente da sala:

```sql
SELECT ROUND(SUM(score * ticket_medio), 2) AS receita_esperada
FROM   lakehouse_rotaperfume.gold.fila_semanal;
-- 556423.71
```

> **Use o botão *Show generated code* em toda resposta.** É o hábito que separa
> quem usa Genie de quem confia em Genie. O número que vai para a reunião é o
> que você conferiu, não o que apareceu na tela.

**6 · O que quebra o job de propósito — o melhor minuto da noite**

```sql
ALTER TABLE lakehouse_rotaperfume.gold.retorno_ligacao
  ALTER COLUMN comentario COMMENT '';
```

```powershell
.\scripts\rodar-tarefa.ps1 <PERFIL> auditoria_de_metadado   # FAILED
```

A mensagem é esta, literal:

```
[USER_RAISED_EXCEPTION] 1 coluna(s) da gold sem COMMENT:
retorno_ligacao.comentario -- documente na instrucao
ALTER TABLE ... ALTER COLUMN ... COMMENT do arquivo que cria a tabela.
```

Devolva o COMMENT e rode de novo: verde. Metadado faltando é bug, não pendência
de documentação — e agora existe uma tarefa que trata isso como bug.

---

## Se der errado

| Sintoma | Causa | Saída |
|---|---|---|
| `bundle deploy` pede para apagar o dashboard | a chave de um recurso existente foi renomeada | Recuse. Volte a chave para `comercial` |
| Deploy falha com erro de ordenação | `tables`, `column_configs` ou as listas de id fora de ordem | Ordene: `identifier`, `column_name`, `id` |
| Deploy falha reclamando de `id` | id com hífen, maiúscula, tamanho ≠ 32, ou repetido entre listas | md5 do conteúdo, minúsculo, e único entre as TRÊS listas somadas |
| `text_instructions must contain at most one item` | mais de uma entrada de instrução | Junte tudo num item só, no array `content` |
| `Tree node with path ... does not exist` | o `parent_path` não existe | `databricks workspace mkdirs /Workspace/Users/<você>/genie` |
| A tarefa `gold_retorno_ligacao` falha | `${catalog}` dentro de um `sql_task` | Nos `.sql` deste bundle o catálogo é **literal**: `lakehouse_rotaperfume` |
| `auditoria_de_metadado` vermelha logo no primeiro run | o backfill dos 65 COMMENT não foi feito, ou foi feito só no arquivo | Rode o job INTEIRO: o CTAS apaga os COMMENT e os recria a cada execução |
| A auditoria passa mas o COMMENT some no dia seguinte | o `ALTER COLUMN` ficou fora do arquivo do CTAS | Os `ALTER` moram no mesmo `.sql` que o `CREATE OR REPLACE`, logo depois dele |
| O Genie novo não acha a fila | a tabela não entrou em `data_sources` | Confira as cinco fontes no JSON |
| O Genie responde com AUC | a instrução não foi explícita | A regra tem que dizer *"NUNCA cite AUC"*, com a palavra nunca, e proibir as cinco colunas pelo nome |
| O Genie inventa retorno | faltou a regra da tabela vazia | Acrescente: *"se for zero, diga que ninguém registrou ainda"* |
| `when --json flag is specified, no positional arguments are allowed` | `job_id` passado como argumento junto com `--json` | Ponha o `job_id` DENTRO do JSON |
| `error decoding JSON at (inline):1:2` | PowerShell comeu as aspas ao repassar o JSON para o executável | Grave o JSON num arquivo e use `--json @arquivo` |
| `invalid character 'ï' looking for beginning of value` | `Set-Content -Encoding utf8` no PS 5.1 escreve BOM | `[System.IO.File]::WriteAllText(..., (New-Object System.Text.UTF8Encoding $false))` |
