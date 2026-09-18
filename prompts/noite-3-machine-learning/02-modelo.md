# Prompt 2 · O modelo e o MLflow

> **Antes de colar:** troque `<PERFIL>`, `<WAREHOUSE_ID>` e `<HOST_DO_WORKSPACE>`
> pelos valores do seu ambiente — a tabela está em
> [prompts/README.md](../README.md#as-variáveis).


**Slides que acompanham:** 23 a 37 (divisor *"O modelo"*, o problema escrito em
uma frase, o algoritmo em três linhas, **por que árvore e não Poisson**, **o que
é AUC**, vazamento de dado, o teste que quase ninguém escreve, divisor
*"MLflow"*, a pergunta de daqui a seis meses, o que o MLflow resolve, o modelo
do lado das tabelas).

**Entrega:** o modelo registrado no Unity Catalog e `gold.score_propensao` —
os 3.000 clientes com nota. **Deploy nº 2 da noite.**

> Este é o prompt do momento da noite. **Segure o baseline até aqui.** Ele é a
> única coisa da aula que a sala não espera.

---

## O ambiente, conferido hoje

Rodado contra `lakehouse_rotaperfume` no workspace. **Tudo o que este prompt
usa já existe** — nenhuma fonte precisa ser criada antes:

| Tabela | O que este prompt lê dela |
|---|---|
| `gold.features_treino` | **2.815** clientes, alvo `comprou_em_7d`, taxa base **10,12%** |
| `gold.features_cliente` | **2.816** clientes, corte 2026-08-31 |

Não há modelo registrado em `gold` — a limpeza levou o `propensao_compra`
antigo e as duas versões dele. O registro vai nascer deste prompt.

O job está com **11 tarefas** e o `bundle deploy` passa limpo — vira **12** com
a `ml_modelo`. O arquivo aqui é `src/ml/10-modelo.py`, seguindo a numeração
sequencial deste repositório (o material original diz `12-modelo.py`).

> **Atenção ao limiar do teste 1.** O material assume que o melhor baseline é
> `valor_total` (~0,62), o que poria o corte do `assert` em ~0,67. **Aqui o
> melhor baseline é `atraso_relativo`, com 0,7842** — o modelo precisa passar de
> **0,8342**. Ele passou (0,8816), mas a margem é bem menor do que parece.

> **No deploy, se aparecer pedido de confirmação para APAGAR O DASHBOARD:
> recuse e me chame.** O dashboard é da noite 2 e a chave do recurso
> (`dashboard_comercial`) não pode ser renomeada — trocar a chave faz o bundle
> apagar e recriar, com URL nova. **Nunca use `--auto-approve` aqui.**

---

## O que mostrar antes

**1 · Peça a resposta da sala — e escreva no quadro**

> *"Sem modelo nenhum. Você tem 200 ligações e 3.000 clientes. Qual coluna você
> ordena?"*

Vem sempre **"quem parou de comprar"** e **"quem compra mais"**. Anote as duas.
Daqui a dez minutos as duas viram número.

**2 · A régua: a taxa base que o prompt 1 mediu**

```sql
SELECT ROUND(100 * AVG(comprou_em_7d), 2) AS taxa_base_pct
FROM lakehouse_rotaperfume.gold.features_treino;
```

**10,11%.** Vinte de cada duzentas.

> *"Se eu sortear 200 nomes num chapéu, essa é a fração que compra sozinha.
> Qualquer coisa que a gente construir hoje precisa ganhar disso — senão o
> projeto não se paga."*

**3 · O corte, desenhado no quadro antes de qualquer código**

```
|---- features até 31/07 ----|CORTE|---- alvo: comprou até 07/08? ----|
                          01/08/2026
```

> *"Se qualquer coluna à esquerda souber de algo à direita, o AUC vem 0,98 e o
> modelo quebra em produção. E não vai aparecer erro nenhum: vai aparecer
> sucesso."*

---

**Enquanto ele trabalha, você explica:**

- **Baseline não é formalidade — é a régua.** "AUC 0,87" não quer dizer nada
  sozinho. "Ganha do que a gente já fazia de graça" quer dizer tudo.
- **A métrica que vai para a reunião é `lift_top200`.** AUC é métrica de quem
  treina. O diretor pergunta quantos dos 200 compraram. São perguntas
  diferentes, e a segunda é a que paga a conta.
- **Vazamento parece sucesso.** É o único erro de ML que chega com print no
  grupo. A defesa não é atenção — é estrutural: função com data por parâmetro,
  coluna `_referencia` gravada, e um teste que **quebra o job se o AUC ≥ 0,99**.
- **O modelo vira objeto de catálogo.** Mesmo catálogo das tabelas, mesmo
  GRANT, mesma linhagem. Não é um `.pkl` no Drive de alguém que saiu da
  empresa.

---

## O prompt

```
Continue o mesmo bundle. As features estão em gold.features_treino e
gold.features_cliente.

Crie src/ml/12-modelo.py — um notebook Python para serverless. Nesta ordem:

1. BASELINE, antes de treinar qualquer coisa.
   Separe 25% de gold.features_treino como holdout, com random_state=42 e
   estratificado pelo alvo. No holdout, calcule roc_auc_score do alvo contra
   cada regra simples, usada como se fosse o score:
     a) -recencia_dias      ("ligue para quem comprou recentemente")
     b)  valor_total        ("ligue para quem compra mais")
     c)  atraso_relativo    ("ligue para quem está atrasado")
   Imprima os três lado a lado, com 0,5000 (a moeda) na mesma tabela.
   Guarde o melhor deles: é a régua do teste 1.

2. TREINO.
   HistGradientBoostingClassifier do scikit-learn, random_state=42.
   NÃO impute NULL: este algoritmo trata NaN nativamente, e as features de
   ritmo são NULL de propósito para quem tem um pedido só.
   NÃO use XGBoost: ele treina e registra, mas falha ao carregar de volta no
   serverless por conflito com scikit-learn 1.6.1 (__sklearn_tags__), e o erro
   só aparece uma tarefa depois.

3. AS DUAS MÉTRICAS.
   auc          — no holdout
   lift_top200  — pontue TODOS os clientes de features_treino por validação
                  cruzada out-of-fold (StratifiedKFold, 5 folds, shuffle,
                  random_state=42), ordene por score, pegue os 200 primeiros e
                  divida a taxa de compra deles pela taxa base.
                  Out-of-fold, e não só o holdout, porque a fila real é de 200
                  entre 3.000 — no holdout de 700 os 200 primeiros seriam 28%
                  da amostra, e o número sairia otimista.
                  Imprima também acertos_top200 (quantos dos 200 compraram).
                  Essa é a métrica que responde a pergunta do diretor.

4. IMPORTÂNCIA POR PERMUTAÇÃO, no holdout, n_repeats=5. Imprima o top 10.

5. MLFLOW.
   Antes de mlflow.set_experiment, crie a pasta pai com
   WorkspaceClient().workspace.mkdirs(...) — sem isso o erro é
   "BAD_REQUEST: For input string: None" e não menciona pasta nenhuma.
   O serverless tem MLflow 2.22: use log_model(..., artifact_path="modelo"),
   nunca o name= do MLflow 3.
   Registre em lakehouse_rotaperfume.gold.propensao_compra com
   mlflow.set_registry_uri("databricks-uc") e aponte o alias @prod para a
   versão recém-criada.
   Logue params, auc, lift_top200, acertos_top200 e a taxa base.

6. TRÊS TESTES QUE INTERROMPEM A TAREFA (assert, com mensagem em português):
   - o modelo ganha do MELHOR baseline por pelo menos 0,05 de AUC
   - auc < 0,99 — bom demais é vazamento, não competência
   - lift_top200 >= 2,5 — abaixo disso a fila não justifica o projeto

7. SCORE.
   Carregue o modelo com mlflow.sklearn.load_model("models:/...@prod") e use
   predict_proba — NÃO use pyfunc.predict, que devolve a classe e transforma
   a coluna inteira em zeros e uns.
   NÃO use mlflow.pyfunc.spark_udf: não roda no serverless
   (InvalidVersion: '18.x-aarch64-photon-scala2'). Traga para pandas: 3.000
   clientes cabem na memória com folga.
   Pontue com EXATAMENTE as colunas do treino, na mesma ordem, lendo
   modelo.feature_names_in_ — não confie na ordem das colunas da tabela.
   Grave gold.score_propensao com cliente_id (INT), score, a faixa
   (NTILE(4) sobre o score: Fria, Morna, Quente, Muito quente), _referencia e
   a versao do modelo — o número que veio do registro no UC.

8. AS MÉTRICAS TAMBÉM VIRAM TABELA — o Genie não lê MLflow, e daqui a seis
   meses ninguém abre a interface de experimento:

   gold.modelo_metricas     uma linha por treino: versao, auc, lift_top200,
                            acertos_top200, taxa_base, o AUC de cada um dos
                            três baselines, a feature nº 1 e _treinado_em
   gold.calibragem_holdout  faixa, clientes, compraram, taxa_de_compra e
                            score_medio, calculados no holdout — é a prova do
                            slide *Não é acurácia*, e a única que o comercial confere sozinho

Tabelas e colunas com COMMENT em português.

Registre a tarefa ml_modelo em resources/pipeline.job.yml, depois de
ml_features, e faça o deploy.
```

---

## Como verificar a feature

**1 · O baseline — o momento da noite**

Está impresso na saída da tarefa. Leia em voz alta, na ordem:

| A resposta | AUC | Dos 200, quantos compram |
|---|---|---|
| "ligue para quem comprou recentemente" (`-recencia_dias`) | **0,3522 — pior que moeda** | **0** |
| "ligue para quem sumiu há mais tempo" | 0,6478 | **0** |
| jogar uma moeda | 0,5000 | 20 |
| "ligue para quem compra mais" (`valor_total`) | 0,6410 | 44 |
| "ligue para quem está atrasado" (`atraso_relativo`) | **0,7842** | **1** |
| **o modelo** | **0,8816** | **84** — 4,15× |

> **Este modelo ainda não era calibrado.** Ele ordenava bem e estimava mal, e
> isso só apareceu depois, no [prompt 4](04-revisao-do-modelo.md). Com a
> calibragem: AUC **0,8840**, **85** — **4,20×**, Brier **0,0709**, ECE **0,0118**.

> **Valores medidos neste workspace**, `seed 42`, corte `2026-08-01`, janela de
> 7 dias, 20 features. A referência do material original (~0,37 · ~0,62 · ~0,85
> · 75 acertos) foi medida fora do Databricks com 12 features — a ordem de
> grandeza bate, os números exatos não. **O que vale é o que sai na tarefa.**

**As duas pontas da recência dão zero.** Não é só "quem sumiu há mais tempo":
ordenar pelos que compraram *mais recentemente* também entrega **nenhum**
comprador em 200 ligações. Os compradores da semana estão no meio da
distribuição, e é isso que nenhuma ordenação de coluna única alcança.

### O gráfico que explica a noite inteira

`atraso_relativo` tem AUC **0,78** e mesmo assim só **1 acerto** nos 200
primeiros. Parece contradição, e não é — a relação é **não-monotônica**:

| Faixa de `atraso_relativo` | Clientes | Compraram | Taxa |
|---|---|---|---|
| < 0,5 — acabou de comprar | 1.244 | 6 | 0,5% |
| 0,5 – 1,0 | 927 | 163 | 17,6% |
| **1,0 – 1,5 — no ponto do próprio ciclo** | 265 | 97 | **36,6%** |
| 1,5 – 3,0 | 97 | 14 | 14,4% |
| ≥ 3,0 — sumiu de vez | 177 | 0 | **0,0%** |

O pico é **3,6× a taxa base** e está **no meio**. Ordenar decrescente põe na
frente justamente o grupo de 0%. Rode esta query antes do prompt: ela justifica
o modelo melhor que qualquer slide, porque mostra que o problema não é falta de
informação — é que a informação não é ordenável.

**Zero.** Dos 200 clientes que sumiram há mais tempo, nenhum comprou na semana
seguinte. Não é "um pouco pior": é a lista inteira desperdiçada.

> **A intuição comercial não está imprecisa — está invertida.** Distribuição
> funciona por ciclo de reposição: quem acabou de receber a mercadoria é
> justamente quem não compra agora. Ninguém tinha medido.

**2 · A prova que o comercial entende, sem falar em AUC**

```sql
SELECT faixa, clientes, compraram,
       ROUND(100 * taxa_de_compra, 1) AS pct_que_comprou
FROM lakehouse_rotaperfume.gold.calibragem_holdout
ORDER BY score_medio;
```

A taxa de compra tem que **subir** da faixa fria para a muito quente. Se sobe,
o score ordena — e ninguém precisa saber o que é curva ROC para conferir.

E a tabela que responde o diretor, com os três números do slide *Não é acurácia* lado a lado:

```sql
SELECT ROUND(100 * taxa_base, 1)      AS pct_aleatorio,
       acertos_top200,
       ROUND(lift_top200, 2)          AS lift,
       ROUND(auc, 4)                  AS auc
FROM lakehouse_rotaperfume.gold.modelo_metricas
ORDER BY _treinado_em DESC LIMIT 1;
```

**3 · O modelo é um objeto do catálogo, não um arquivo**

```bash
databricks registered-models list \
  --catalog-name lakehouse_rotaperfume --schema-name gold --profile <perfil>
```

> `SHOW MODELS` **não existe em SQL** — dá `PARSE_SYNTAX_ERROR`. Modelo do
> Unity Catalog se lista pela CLI ou pela tela do Catalog Explorer.

Abra a tela do modelo no workspace ao lado da tela da tabela. **Mesmo
catálogo, mesma linhagem, mesmo GRANT.** É o slide *“Esse modelo ainda está bom?”* respondido: qual versão
está em produção, com que dado, treinada quando e por quem.

**4 · O teste que desconfia do sucesso**

Mostre a linha do `assert auc < 0.99` no código:

> *"Este job quebra se o resultado ficar bom demais. É a única defesa que
> funciona contra vazamento, porque vazamento não chega com erro — chega com
> elogio."*

---

## Se der errado

| Sintoma | Causa | Saída |
|---|---|---|
| `BAD_REQUEST: For input string: "None"` | `set_experiment` não cria a pasta pai | `WorkspaceClient().workspace.mkdirs(...)` antes |
| `AttributeError: __sklearn_tags__` | XGBoost registrado, sklearn 1.6.1 na carga | trocar por `HistGradientBoostingClassifier` |
| `InvalidVersion: '18.x-aarch64-photon-scala2'` | `pyfunc.spark_udf` no serverless | `mlflow.sklearn.load_model` + pandas |
| `score` só com 0 e 1 | `pyfunc.predict` devolve a classe | `predict_proba()[:, 1]` |
| `Object of type Decimal is not JSON serializable` | feature `DECIMAL` no registro | `.cast("double")` no prompt 1 |
| O assert do baseline quebrou o job | o modelo não ganhou da regra simples | **não conserte ao vivo** — é a aula acontecendo. Mostre a mensagem e discuta |
| `roc_auc_score` reclama de `NaN` | `atraso_relativo` é nulo para quem tem um pedido só | impute a **mediana só no cálculo do baseline**, para as três regras serem medidas na mesma população. O modelo continua recebendo o `NaN` |
| `latest_versions` volta vazio ou dá erro | o registry do Unity Catalog não suporta essa API | registre em passo separado: `mlflow.register_model(...).version` devolve a versão |
| `bin edges must be unique` no `qcut` | muitos scores empatados em zero | `qcut` sobre `score.rank(method="first")` |
| `PARSE_SYNTAX_ERROR` ao aplicar `COMMENT` | aspas simples dentro do texto encerram o literal SQL | dobre as aspas antes de montar o comando |