# Prompt 1 · Raw — o catálogo vira código e o dado chega ao Volume

**Entrega:** o bundle existe, o catálogo inteiro é código, os 10 CSVs estão no
Volume e o job `rotaperfume_pipeline` roda com a primeira tarefa. **Deploy nº 1.**

> **O momento "agora entendi".** Ontem eles clicaram em *Create catalog*, depois
> em *Create schema*, três vezes. Hoje o catálogo inteiro são trinta linhas de
> YAML que sobem em trinta segundos — e sobem iguais na máquina de qualquer um.

---

## O que mostrar antes

Abra o Catalog Explorer **antes de colar o prompt**. Não tem
nada lá. É esse o ponto de partida, e é o contraste que faz o resto da noite.

```bash
# 1. o catálogo da noite não existe
databricks catalogs list --profile projeto-dados-ia | grep rotaperfume || echo 'não existe'

# 2. os 10 CSVs existem, mas só na sua máquina
ls -1 dados/erp dados/crm
du -sh dados/                      # ~14,7 MB
```

```sql
-- 3. a prova de que não há nada no workspace: o erro que a gente QUER ver agora
SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.clientes;
-- [TABLE_OR_VIEW_NOT_FOUND] · Catalog 'lakehouse_rotaperfume' was not found
```

**A pergunta para a sala, antes de rodar:** *"ontem vocês criaram catálogo e
schema clicando. Se esse workspace sumisse agora, quanto tempo levaria para
refazer tudo — e vocês lembrariam de todos os cliques, na ordem certa?"*

---

**Enquanto ele trabalha, você explica:**

- **Raw não é bronze.** Raw é *arquivo*; bronze é *tabela*. O Volume guarda o CSV
  exatamente como saiu do ERP, byte por byte. Se amanhã alguém perguntar "esse
  número veio de onde?", a resposta é um arquivo, não uma opinião.
- **Por que Volume e não DBFS.** Volume é objeto do Unity Catalog: tem dono, tem
  permissão, aparece na linhagem. DBFS é uma pasta sem sobrenome.
- **Conferência de chegada.** O erro mais caro de pipeline não é o que quebra —
  é o arquivo que não chegou e ninguém viu. Ele não dá erro: dá número menor, e
  o dashboard mostra metade da receita com cara de número certo.

---

## O prompt

```
Leia aulas/aula-02-engenharia-de-dados/prd/CLAUDE.md antes de começar.

Crie o projeto da noite 2 em aulas/aula-02-engenharia-de-dados/rotaperfume/,
como um Databricks Asset Bundle. Esta é a primeira de seis entregas — as outras
cinco estendem este mesmo bundle, então deixe a estrutura pronta para crescer.

O ambiente está ZERADO: o catálogo não existe. Crie tudo.

CONTEXTO DO WORKSPACE
- profile: projeto-dados-ia   (sempre passe --profile, nunca deixe implícito)
- host: https://dbc-84cd5511-fa25.cloud.databricks.com
- SQL Warehouse: 666be37e3fededf2 (Serverless Starter Warehouse)
- Databricks Free Edition: tudo serverless, nunca configure cluster

1. databricks.yml
   - bundle name: rotaperfume
   - variables: catalog (default lakehouse_rotaperfume) e warehouse_id
     (default 666be37e3fededf2)
   - targets dev (default) e prod
   - include: resources/*.yml

   ARMADILHA IMPORTANTE: NÃO use `mode: development` no target dev. Ele prefixa
   o nome dos recursos com [dev seu_usuario] — inclusive os SCHEMAS do Unity
   Catalog, que virariam dev_fulano_bronze e quebrariam todo o SQL da noite.
   Em vez disso, pause o agendamento explicitamente com
   `presets: { trigger_pause_status: PAUSED }`. Deixe um comentário no YAML
   explicando isso, porque é o tipo de coisa que só se descobre errando.

2. scripts/criar-catalogo.sh
   Cria o catálogo com `CREATE CATALOG IF NOT EXISTS`, via
   `databricks experimental aitools tools query`. Recebe o profile como
   primeiro argumento.

   POR QUE NÃO ESTÁ NO BUNDLE: no Free Edition o Default Storage está ligado,
   e nessa configuração a API do Unity Catalog RECUSA criar catálogo — ela
   exige um MANAGED LOCATION que a conta gratuita não tem:
     Error: Metastore storage root URL does not exist.
            Default Storage is enabled in your account. (400 INVALID_STATE)
   O comando SQL funciona. Deixe esse motivo comentado no script.

3. resources/catalogo.yml — o resto do catálogo como recurso do bundle:
   - schemas: bronze, silver e gold
   - volumes: bronze.raw, do tipo MANAGED
   COMMENT em todos, explicando o papel de cada camada em uma frase.

4. scripts/subir-raw.sh
   Sobe os CSVs de dados/erp e dados/crm (na raiz do repositório) para
   /Volumes/{catalog}/bronze/raw/erp e /crm.
   Use `databricks fs cp --recursive --overwrite` — e lembre que o comando
   exige o esquema `dbfs:` no destino, mesmo sendo um Volume do UC.
   Se dados/ não existir, gere antes com
   `python3 material/gerar_dataset.py --saida ./dados --seed 42`.
   O profile é o primeiro argumento, sem default.

5. src/raw/conferencia.py
   Notebook Python serverless (cabeçalho `# Databricks notebook source`) que faz
   a CONFERÊNCIA DE CHEGADA do raw:
   - lê o parâmetro catalog via dbutils.widgets
   - confere que os 10 arquivos esperados existem no Volume
     (erp: produtos, pedidos, itens_pedido, pagamentos, estoque;
      crm: clientes, vendedores, carteira, oportunidades, visitas)
   - para cada um: tamanho em bytes e número de linhas de dado
   - grava a tabela de controle bronze._raw_arquivos com
     (sistema, arquivo, bytes, linhas, conferido_em) e COMMENT
   - se faltar arquivo ou algum vier vazio, levante exceção e interrompa
   - imprime uma tabela legível ao final

6. resources/pipeline.job.yml
   O job rotaperfume_pipeline, com UMA tarefa: raw_conferencia. Serverless.
   Agendamento diário às 6h, timezone America/Sao_Paulo.
   Este job ganha tarefas nos próximos cinco prompts — escreva isso num
   comentário no topo do YAML, com o desenho de como ele vai ficar.

7. Rode NESTA ORDEM e me mostre a saída de cada passo:
   bash scripts/criar-catalogo.sh projeto-dados-ia
   databricks bundle validate --target dev --profile projeto-dados-ia
   databricks bundle deploy   --target dev --profile projeto-dados-ia
   bash scripts/subir-raw.sh  projeto-dados-ia
   databricks bundle run rotaperfume_pipeline --target dev --profile projeto-dados-ia

A ordem importa duas vezes: o catálogo tem que existir antes do deploy criar os
schemas, e o Volume tem que existir antes de subir arquivo nele.

Não crie a camada bronze ainda. Hoje o dado só chega no Volume.
```

---

## Como verificar a feature

Cinco verificações, nessa ordem. Cada uma prova uma coisa diferente — e as duas
últimas são as que a turma lembra na semana seguinte.

**1 · O catálogo inteiro existe, e nasceu de trinta linhas de YAML**

```sql
SHOW SCHEMAS IN lakehouse_rotaperfume;          -- bronze, silver, gold
DESCRIBE VOLUME lakehouse_rotaperfume.bronze.raw;

-- e o COMMENT que o YAML declarou, que é o que documenta a camada
SELECT schema_name, comment
FROM lakehouse_rotaperfume.information_schema.schemata
WHERE schema_name IN ('bronze','silver','gold');
```

**2 · Os 10 arquivos chegaram ao Volume**

```sql
LIST '/Volumes/lakehouse_rotaperfume/bronze/raw/erp';
LIST '/Volumes/lakehouse_rotaperfume/bronze/raw/crm';
```

```bash
databricks fs ls dbfs:/Volumes/lakehouse_rotaperfume/bronze/raw/erp --profile projeto-dados-ia
```

**3 · A conferência de chegada registrou o que chegou**

```sql
SELECT sistema, arquivo, bytes, linhas, conferido_em
FROM lakehouse_rotaperfume.bronze._raw_arquivos
ORDER BY linhas DESC;

SELECT COUNT(*)                        AS arquivos,
       SUM(linhas)                     AS linhas_de_dado,
       ROUND(SUM(bytes)/1024/1024, 1)  AS mb
FROM lakehouse_rotaperfume.bronze._raw_arquivos;
```

| O que aparece | Valor | Query que mostra |
|---|---|---|
| Arquivos conferidos | **10** | `SELECT COUNT(*) FROM bronze._raw_arquivos` |
| Linhas de dado | **313.551** | `SELECT SUM(linhas) FROM bronze._raw_arquivos` |
| Tamanho total | **14,7 MB** | `SELECT ROUND(SUM(bytes)/1024/1024,1) FROM bronze._raw_arquivos` |
| Maior arquivo | **itens_pedido.csv · 197.724** | `... ORDER BY linhas DESC LIMIT 1` |

**4 · A prova de que é código, não clique — apague e traga de volta**

```sql
DROP SCHEMA lakehouse_rotaperfume.gold;    -- ainda está vazio, é seguro fazer ao vivo
SHOW SCHEMAS IN lakehouse_rotaperfume;     -- gold sumiu
```

```bash
databricks bundle deploy --target dev --profile projeto-dados-ia
```

```sql
SHOW SCHEMAS IN lakehouse_rotaperfume;     -- gold voltou idêntico, em segundos
```

**5 · A prova de que a conferência serve para alguma coisa — quebre de propósito**

```bash
databricks fs rm dbfs:/Volumes/lakehouse_rotaperfume/bronze/raw/erp/pagamentos.csv \
  --profile projeto-dados-ia
databricks bundle run rotaperfume_pipeline --target dev --profile projeto-dados-ia
# a tarefa raw_conferencia FALHA e o job para: falta pagamentos.csv
bash scripts/subir-raw.sh projeto-dados-ia     # devolve o arquivo e rode de novo
```

> Diga isso enquanto o job está vermelho: *"sem essa tarefa, o pipeline seguiria
> verde, a bronze teria nove tabelas em vez de dez, e o dashboard mostraria um
> faturamento menor — com cara de número certo."*

---

## Fala de aula

> *"Repara no que acabou de acontecer: eu não cliquei em lugar nenhum. O
> catálogo, os três schemas e o volume viraram trinta linhas de YAML. E olha o
> que eu ganho de brinde — se eu apagar tudo agora, um `deploy` traz de volta
> idêntico. Ontem, se alguém apagasse aquele catálogo, a gente refazia clicando.*
>
> *E tem uma tarefa aí que não faz nada de bonito: ela só confere se os dez
> arquivos chegaram. É a tarefa mais chata do pipeline e a que mais salva
> emprego. Arquivo que não chega não dá erro — ele dá número menor."*


---

## Se der errado

| Sintoma | Causa | Correção em um prompt |
|---|---|---|
| `Metastore storage root URL does not exist` no deploy | O bundle tentou criar o catálogo pela API | *"Tire o catálogo do bundle e crie por SQL num script."* |
| Os schemas viraram `dev_seunome_bronze` | `mode: development` no target dev | *"Tire o `mode: development` e pause o agendamento com `presets: trigger_pause_status: PAUSED`."* |
| `Tree node does not exist` | A pasta do workspace não existe | Rode `databricks workspace mkdirs` antes |
| `databricks fs cp` reclama do caminho | Faltou o esquema `dbfs:` no destino | O destino é `dbfs:/Volumes/...`, mesmo sendo Volume do UC |

**Tempo medido:** ~1min de deploy, ~40s de upload, ~1min30 de execução do job.