# Prompt 2 · Bronze — o arquivo vira tabela, e a conta tem que fechar

**Entrega:** os 10 CSVs do Volume viram 10 tabelas em `bronze`, cada uma com
metadado de origem, e o job ganha a segunda tarefa — que **falha** se a contagem
não bater com a conferência da noite passada. **Deploy nº 2.**

> **O momento "agora entendi".** Ontem o dado chegou, mas continuou sendo
> arquivo: para olhar dentro dele você precisava saber o caminho no Volume. Hoje
> ele é tabela — responde `SELECT`, tem coluna com nome, aparece na linhagem. E
> a passagem de um para o outro não é confiança: é conferência.

---

## O que mostrar antes

Abra o Catalog Explorer em `lakehouse_rotaperfume.bronze` **antes de colar o
prompt**. Tem exatamente uma tabela lá: `_raw_arquivos`, a de controle da noite
passada. Nenhuma tabela de dado.

```sql
-- 1. a bronze tem controle, mas não tem dado
SHOW TABLES IN lakehouse_rotaperfume.bronze;

-- 2. o erro que a gente QUER ver agora
SELECT * FROM lakehouse_rotaperfume.bronze.clientes LIMIT 5;
-- [TABLE_OR_VIEW_NOT_FOUND] · bronze.clientes

-- 3. mas o número que a bronze vai ter que respeitar já existe desde ontem
SELECT SUM(linhas) FROM lakehouse_rotaperfume.bronze._raw_arquivos;  -- 313.551
```

**A pergunta para a sala, antes de rodar:** *"daqui a pouco vão existir dez
tabelas aí. Como vocês vão saber que não faltou linha nenhuma no caminho? Uma
tabela com metade das linhas responde `SELECT` igualzinho."*

---

**Enquanto ele trabalha, você explica:**

- **Raw é arquivo, bronze é tabela.** O Volume continua lá, intacto, com o CSV
  byte por byte. A bronze não substitui o arquivo — ela dá a ele um formato que
  o resto do lakehouse consegue consultar, versionar e rastrear.
- **Por que tudo entra como texto.** Bronze é o dado *como ele chegou*. Se o CRM
  mandou o CNPJ com espaço na frente, ele entra com espaço. Se `ativo` é `S` e
  `N` em vez de booleano, entra `S` e `N`. Conserto disso é a silver — e
  conserto cedo demais é conserto que ninguém revisa: a sujeira some antes de
  alguém ver que ela existia.
- **Por que cada linha carrega de onde veio.** `_arquivo_origem` e
  `_ingerido_em` respondem "esse número veio de onde?" dentro da própria tabela,
  sem depender de ninguém lembrar qual arquivo foi carregado quando.
- **Por que a conta tem que fechar.** Este é o ponto da noite. A tarefa de ontem
  registrou quantas linhas chegaram. A de hoje conta quantas foram gravadas e
  compara. Sem essa comparação, uma linha perdida na leitura não aparece em
  lugar nenhum: a tabela existe, responde consulta, e só está errada.

---

## O prompt

```
Leia CLAUDE.md antes de começar. A entrega 1 já está no ar: o catálogo é código,
os 10 CSVs estão em /Volumes/lakehouse_rotaperfume/bronze/raw/{erp,crm} e a
tabela bronze._raw_arquivos registra 10 arquivos e 313.551 linhas de dado.

Esta é a entrega 2 de seis. Estenda o MESMO bundle, em rotaperfumes/.

CONTEXTO DO WORKSPACE
- profile: rotaperfumes   (sempre passe --profile, nunca deixe implícito)
- catálogo: lakehouse_rotaperfume
- Databricks Free Edition: tudo serverless, nunca configure cluster

1. src/bronze/ingestao.py
   Notebook Python serverless (cabeçalho "# Databricks notebook source") que lê
   os 10 CSVs do Volume e grava 10 tabelas em bronze — uma por arquivo, com o
   mesmo nome do arquivo.

   REGRAS DA CAMADA, e elas importam:
   - TODA coluna entra como STRING. Nada de inferSchema. Bronze é o dado como
     ele chegou; tipagem é silver.
   - mode=FAILFAST na leitura: linha malformada tem que explodir alto, não
     virar NULL silencioso.
   - acrescente _arquivo_origem (de _metadata.file_path) e _ingerido_em.
   - COMMENT em cada tabela, dizendo de qual arquivo e de qual sistema veio.
   - escrita com overwrite: rodar duas vezes tem que dar o mesmo resultado.

2. A RECONCILIAÇÃO — é o coração da noite
   Depois de gravar, compare a contagem de cada tabela bronze com a coluna
   "linhas" de bronze._raw_arquivos, que a entrega 1 preencheu.
   Se qualquer par divergir, LEVANTE EXCEÇÃO dizendo arquivo, esperado e obtido.
   Grave o resultado em bronze._bronze_carga com
   (sistema, tabela, linhas_esperadas, linhas_gravadas, ingerido_em) e COMMENT.
   Grave a tabela de controle ANTES de decidir se falha: numa execução que
   quebra, o registro do que divergiu é justamente o que interessa.

3. resources/pipeline.job.yml
   Acrescente a tarefa bronze_ingestao ao job rotaperfume_pipeline, com
   depends_on em raw_conferencia — nada de bronze antes da conferência dizer
   que o arquivo chegou. Atualize o mapa das seis entregas no comentário do topo.

4. Rode e me mostre a saída:
   databricks bundle validate --strict --target dev --profile rotaperfumes
   databricks bundle deploy --target dev --profile rotaperfumes
   databricks bundle run rotaperfume_pipeline --target dev --profile rotaperfumes

Não crie a camada silver. Hoje o dado vira tabela, e continua sujo de propósito.
```

---

## Como verificar a feature

**1 · As dez tabelas existem, e sabem de onde vieram**

```sql
SHOW TABLES IN lakehouse_rotaperfume.bronze;
-- 10 tabelas de dado + _raw_arquivos + _bronze_carga

DESCRIBE TABLE EXTENDED lakehouse_rotaperfume.bronze.clientes;
-- toda coluna STRING, mais _arquivo_origem e _ingerido_em, e o COMMENT
```

**2 · A conta fecha — a verificação que dá nome à noite**

```sql
SELECT sistema, tabela, linhas_esperadas, linhas_gravadas,
       linhas_gravadas - linhas_esperadas AS diferenca
FROM lakehouse_rotaperfume.bronze._bronze_carga
ORDER BY linhas_gravadas DESC;
-- diferenca = 0 nas dez

SELECT COUNT(*) AS tabelas, SUM(linhas_gravadas) AS linhas
FROM lakehouse_rotaperfume.bronze._bronze_carga;
```

| O que aparece | Valor |
|---|---|
| Tabelas carregadas | **10** |
| Linhas na bronze | **313.551** |
| Diferença para a conferência de chegada | **0** |
| Maior tabela | **itens_pedido · 197.724** |

**3 · O dado chegou sujo, de propósito**

```sql
SELECT cliente_id, cnpj, length(cnpj) AS tamanho
FROM lakehouse_rotaperfume.bronze.clientes LIMIT 5;
-- o CNPJ vem com espaço antes e depois, e a bronze preservou
```

> *"Isso aqui é feio, e é para estar feio. Se eu tivesse limpado agora, ninguém
> nesta sala saberia que o CRM manda CNPJ com espaço. Semana que vem, quando a
> silver tirar esses espaços, vai ser uma decisão registrada — não um acidente."*

**4 · A origem viaja junto com a linha**

```sql
SELECT DISTINCT _arquivo_origem FROM lakehouse_rotaperfume.bronze.pedidos;
-- dbfs:/Volumes/lakehouse_rotaperfume/bronze/raw/erp/pedidos.csv
```

Uma linha, uma origem — e repare no prefixo `dbfs:`, que o Spark devolve mesmo
sendo Volume do Unity Catalog. É o mesmo esquema que o `databricks fs cp` exigiu
na noite passada.

**5 · A prova de que a reconciliação serve para alguma coisa — quebre de propósito**

Duas quebras, e elas ensinam coisas diferentes.

```sql
-- a) alguém "arrumou" a tabela na mão
-- CAST porque na bronze vendedor_id é STRING: sem ele, '5' > '40' é verdadeiro
DELETE FROM lakehouse_rotaperfume.bronze.vendedores WHERE CAST(vendedor_id AS INT) > 30;
SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.vendedores;   -- 30, não 42
```

```bash
# rode o job de novo: a carga regrava a tabela inteira e a conta volta a fechar
databricks bundle run rotaperfume_pipeline --target dev --profile rotaperfumes
```

```bash
# b) o Volume mudou depois da última conferência — rode SÓ a carga da bronze.
#    (trunque pagamentos.csv para 100 linhas e suba para o Volume antes disto)
# o job_id vai DENTRO do JSON: com --json a CLI não aceita argumento posicional
databricks jobs run-now --profile rotaperfumes \
  --json '{"job_id":<job_id>,"only":["bronze_ingestao"]}'
# a tarefa bronze_ingestao FALHA, e a mensagem é exatamente esta:
#   RuntimeError: A bronze nao fecha com a conferencia de chegada -- 1 divergencia(s):
#     - erp/pagamentos: esperado 27,772 linhas, gravado 100
#
# pegue o job_id com:
#   databricks jobs list --profile rotaperfumes
```

```powershell
.\scripts\subir-raw.ps1 rotaperfumes   # devolve o arquivo inteiro e rode de novo
```

> Diga isso enquanto o job está vermelho: *"repara que a tabela foi criada. Ela
> existe, ela responde `SELECT`, ela tem cara de tabela certa. A única coisa
> entre esse número errado e o dashboard da diretoria é essa comparação."*

**Por que `--only` e não o job inteiro — e aqui vem a melhor pergunta da noite.**
Se você rodar o job **completo** com o arquivo truncado, ele fica **verde**. Não
é bug: `raw_conferencia` roda primeiro e *reescreve* `_raw_arquivos` a partir do
mesmo arquivo truncado. A expectativa vira 100, a bronze grava 100, os dois
números concordam.

```sql
-- o que um job verde registrou, com o arquivo truncado:
SELECT tabela, linhas_esperadas, linhas_gravadas
FROM lakehouse_rotaperfume.bronze._bronze_carga WHERE tabela = 'pagamentos';
-- 100 | 100  ... e tudo "bate"

SELECT SUM(linhas_gravadas) FROM lakehouse_rotaperfume.bronze._bronze_carga;
-- 285.879, e não 313.551
```

> **Mostre isso à sala e deixe o silêncio trabalhar:** *"o pipeline está verde. A
> conferência conferiu. A reconciliação reconciliou. E sumiram vinte e sete mil
> pagamentos. Por quê?"*
>
> Porque a reconciliação de hoje compara **o Volume com a bronze, na mesma
> execução**. Ela pega linha perdida na leitura. Ela não tem como saber que o
> arquivo chegou menor — para isso ela precisaria de uma memória do que era
> normal ontem. Isso tem nome, chama-se linha de base, e é assunto da noite de
> qualidade.

Guarde esse `285.879` no quadro. É o gancho da entrega 5.

---

## Fala de aula

> *"Ontem eu disse que arquivo que não chega não dá erro. Hoje é a versão dois
> disso: linha que não é lida também não dá erro. A tabela existe do mesmo
> jeito, responde consulta do mesmo jeito — só está errada.*
>
> *Por isso a bronze não termina no `write`. Ela termina na comparação.
> Trezentas e treze mil, quinhentas e cinquenta e uma linhas entraram no Volume
> ontem; trezentas e treze mil, quinhentas e cinquenta e uma estão nas tabelas
> hoje. Se um dia esses dois números discordarem, o pipeline para — e alguém vai
> olhar antes do diretor olhar.*
>
> *E vocês viram o buraco que sobrou: se o arquivo já chega menor, os dois
> números concordam no valor errado, e o verde mente. Conferir contra si mesmo
> tem limite. Guardem isso — é a próxima pergunta que a gente vai ter que
> responder."*

---

## Se der errado

| Sintoma | Causa | Correção em um prompt |
|---|---|---|
| `TABLE_OR_VIEW_NOT_FOUND: bronze._raw_arquivos` | A tarefa `raw_conferencia` nunca rodou nesta workspace | *"Rode a entrega 1 primeiro: o job inteiro, não só a tarefa nova."* |
| Colunas viraram `int`/`double` sozinhas | Ficou `inferSchema=true` na leitura | *"Leia tudo como STRING, sem inferir tipo: bronze é o dado como chegou."* |
| A contagem dá uma linha a mais por tabela | O cabeçalho está entrando como dado | *"Passe `header=true` na leitura do CSV."* |
| `_metadata.file_path` não existe | A coluna de metadados foi pedida depois de uma agregação | *"Acrescente `_arquivo_origem` logo na leitura, antes de qualquer transformação."* |
| A tarefa nova rodou antes da conferência | Faltou `depends_on` | *"Ponha `depends_on: raw_conferencia` na tarefa `bronze_ingestao`."* |
| A primeira consulta da aula demora ~1min | O SQL Warehouse serverless estava frio | Rode um `SELECT 1` alguns minutos antes da aula para acordar |

**Tempo medido:** ~6s de deploy, ~2min30 de execução do job com as duas tarefas.
