# Databricks notebook source
# MAGIC %md
# MAGIC # O modelo e o MLflow
# MAGIC
# MAGIC **Baseline nao e formalidade, e a regua.** "AUC 0,87" nao quer dizer nada
# MAGIC sozinho; "ganha do que a gente ja fazia de graca" quer dizer tudo. Por
# MAGIC isso este notebook mede as regras simples ANTES de treinar qualquer coisa.
# MAGIC
# MAGIC **A metrica que vai para a reuniao e `lift_top200`.** AUC e metrica de
# MAGIC quem treina. O diretor pergunta quantos dos 200 compraram -- sao perguntas
# MAGIC diferentes, e a segunda e a que paga a conta.
# MAGIC
# MAGIC **Vazamento parece sucesso.** E o unico erro de ML que chega com print no
# MAGIC grupo. A defesa nao e atencao, e estrutural: features com data por
# MAGIC parametro (prompt 1) e um `assert` que quebra o job se o AUC vier alto
# MAGIC demais.

# COMMAND ----------

import mlflow
import numpy as np
import pandas as pd
from databricks.sdk import WorkspaceClient
from mlflow.tracking import MlflowClient
from pyspark.sql import functions as F
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.inspection import permutation_importance
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import StratifiedKFold, cross_val_predict, train_test_split

# COMMAND ----------

dbutils.widgets.text("catalog", "lakehouse_rotaperfume", "Catalogo")
catalog = dbutils.widgets.get("catalog").strip()
if not catalog:
    raise ValueError("O parametro 'catalog' chegou vazio.")

MODELO_UC = f"{catalog}.gold.propensao_compra"
ALVO = "comprou_em_7d"
TOP_N = 200  # a fila que o time consegue atacar por semana
SEMENTE = 42

treino_pdf = spark.table(f"{catalog}.gold.features_treino").toPandas()
referencia_treino = treino_pdf["_referencia"].iloc[0]

FEATURES = [c for c in treino_pdf.columns if c not in ("cliente_id", ALVO, "_referencia")]
X = treino_pdf[FEATURES].astype("float64")
y = treino_pdf[ALVO].astype(int)

taxa_base = float(y.mean())
print(f"{len(treino_pdf):,} clientes | corte {referencia_treino} | {len(FEATURES)} features")
print(f"taxa base: {100 * taxa_base:.2f}%  ->  de 200 ligacoes as cegas, {round(TOP_N * taxa_base)} viram pedido")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 1 · O baseline, antes de treinar
# MAGIC
# MAGIC As duas respostas que sempre vem da sala -- "quem parou de comprar" e
# MAGIC "quem compra mais" -- viram numero aqui.

# COMMAND ----------

X_tr, X_te, y_tr, y_te = train_test_split(X, y, test_size=0.25, random_state=SEMENTE, stratify=y)

# `roc_auc_score` nao aceita NaN, e `atraso_relativo` e nulo de proposito para
# quem tem um pedido so. Imputamos a MEDIANA apenas para medir o baseline, para
# que as tres regras sejam avaliadas sobre exatamente a mesma populacao. O
# modelo, mais abaixo, continua recebendo o NaN original.
REGRAS = {
    "-recencia_dias  (ligue para quem comprou recentemente)": -X_te["recencia_dias"],
    "valor_total     (ligue para quem compra mais)": X_te["valor_total"],
    "atraso_relativo (ligue para quem esta atrasado)": X_te["atraso_relativo"].fillna(X_tr["atraso_relativo"].median()),
}

baselines = {nome: float(roc_auc_score(y_te, serie)) for nome, serie in REGRAS.items()}
baselines["moeda           (sortear 200 nomes no chapeu)"] = 0.5

print("BASELINE  --  AUC no holdout\n")
for nome, auc_b in sorted(baselines.items(), key=lambda kv: kv[1]):
    print(f"  {auc_b:.4f}   {nome}")

melhor_baseline_nome = max(baselines, key=baselines.get)
melhor_baseline = baselines[melhor_baseline_nome]
print(f"\nmelhor baseline: {melhor_baseline:.4f}  ({melhor_baseline_nome.split('(')[0].strip()})")

# E o numero que o comercial entende: dos 200 primeiros de cada regra, quantos
# compraram de fato. AUC alto NAO garante acerto no topo da fila -- e a tabela
# abaixo costuma provar isso melhor que qualquer slide.
print("\nDOS 200 PRIMEIROS, QUANTOS COMPRARAM  (base completa)\n")
for rotulo, serie in {
    "sumiu ha mais tempo": X["recencia_dias"],
    "comprou recentemente": -X["recencia_dias"],
    "compra mais": X["valor_total"],
    "mais atrasado": X["atraso_relativo"].fillna(-np.inf),
}.items():
    topo = y.iloc[np.argsort(-serie.to_numpy())[:TOP_N]].sum()
    print(f"  {int(topo):>4}   {rotulo}")
print(f"  {round(TOP_N * taxa_base):>4}   aleatorio (esperado)")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 2 · O treino
# MAGIC
# MAGIC `HistGradientBoostingClassifier` trata `NaN` nativamente, entao as features
# MAGIC de ritmo continuam nulas para quem tem um pedido so -- que e a resposta
# MAGIC honesta, e nao zero.
# MAGIC
# MAGIC Nao use XGBoost: ele treina e registra, mas falha ao CARREGAR de volta no
# MAGIC serverless por conflito com o scikit-learn 1.6.1 (`__sklearn_tags__`), e o
# MAGIC erro so aparece uma tarefa depois.

# COMMAND ----------


def novo_modelo() -> HistGradientBoostingClassifier:
    return HistGradientBoostingClassifier(random_state=SEMENTE)


modelo = novo_modelo().fit(X_tr, y_tr)
auc = float(roc_auc_score(y_te, modelo.predict_proba(X_te)[:, 1]))
print(f"AUC do modelo no holdout: {auc:.4f}")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 3 · `lift_top200` — a metrica que responde o diretor
# MAGIC
# MAGIC Out-of-fold, e nao so no holdout: a fila real e de 200 entre 2.815. No
# MAGIC holdout de ~700, os 200 primeiros seriam quase um terco da amostra e o
# MAGIC numero sairia otimista.

# COMMAND ----------

folds = StratifiedKFold(n_splits=5, shuffle=True, random_state=SEMENTE)
score_oof = cross_val_predict(novo_modelo(), X, y, cv=folds, method="predict_proba")[:, 1]

topo = np.argsort(-score_oof)[:TOP_N]
acertos_top200 = int(y.iloc[topo].sum())
taxa_topo = acertos_top200 / TOP_N
lift_top200 = float(taxa_topo / taxa_base)

print(f"acertos_top200: {acertos_top200} de {TOP_N}  ({100 * taxa_topo:.1f}%)")
print(f"taxa base     : {100 * taxa_base:.2f}%")
print(f"lift_top200   : {lift_top200:.2f}x")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 4 · Importancia por permutacao

# COMMAND ----------

imp = permutation_importance(modelo, X_te, y_te, n_repeats=5, random_state=SEMENTE, scoring="roc_auc")
ranking = sorted(zip(FEATURES, imp.importances_mean), key=lambda kv: -kv[1])

print("TOP 10 FEATURES (queda de AUC ao embaralhar a coluna)\n")
for nome, valor in ranking[:10]:
    print(f"  {valor:+.4f}   {nome}")

feature_top1 = ranking[0][0]

# COMMAND ----------

# MAGIC %md
# MAGIC ## 5 · MLflow — o modelo vira objeto de catalogo
# MAGIC
# MAGIC Mesmo catalogo das tabelas, mesmo GRANT, mesma linhagem. Nao e um `.pkl`
# MAGIC no Drive de alguem que saiu da empresa.

# COMMAND ----------

usuario = WorkspaceClient().current_user.me().user_name
pasta = f"/Users/{usuario}/rotaperfume"
# `set_experiment` NAO cria a pasta pai. Sem este mkdirs o erro e
# "BAD_REQUEST: For input string: None", que nao menciona pasta nenhuma.
WorkspaceClient().workspace.mkdirs(pasta)

mlflow.set_registry_uri("databricks-uc")
mlflow.set_experiment(f"{pasta}/propensao_compra")

with mlflow.start_run(run_name=f"propensao_{referencia_treino}") as run:
    mlflow.log_params(
        {
            "algoritmo": "HistGradientBoostingClassifier",
            "random_state": SEMENTE,
            "n_features": len(FEATURES),
            "referencia": str(referencia_treino),
            "janela_alvo_dias": 7,
        }
    )
    mlflow.log_metrics(
        {
            "auc": auc,
            "lift_top200": lift_top200,
            "acertos_top200": acertos_top200,
            "taxa_base": taxa_base,
            "melhor_baseline_auc": melhor_baseline,
        }
    )
    # O serverless tem MLflow 2.x: `artifact_path`, nunca o `name=` do MLflow 3.
    mlflow.sklearn.log_model(modelo, artifact_path="modelo", input_example=X_tr.head(3))
    run_id = run.info.run_id

# Registrar em passo separado devolve a versao criada. `latest_versions` do
# MlflowClient NAO funciona no registry do Unity Catalog.
versao = mlflow.register_model(f"runs:/{run_id}/modelo", MODELO_UC).version
MlflowClient().set_registered_model_alias(MODELO_UC, "prod", versao)
print(f"registrado: {MODELO_UC} versao {versao}, alias @prod")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 6 · Os tres testes que interrompem a tarefa
# MAGIC
# MAGIC O segundo e o mais importante da noite: **este job quebra se o resultado
# MAGIC ficar bom demais**. E a unica defesa que funciona contra vazamento, porque
# MAGIC vazamento nao chega com erro -- chega com elogio.

# COMMAND ----------

assert auc >= melhor_baseline + 0.05, (
    f"O modelo nao justifica o projeto: AUC {auc:.4f} contra {melhor_baseline:.4f} do melhor "
    f"baseline ({melhor_baseline_nome.split('(')[0].strip()}). "
    "Uma regra de uma linha faz quase o mesmo -- e sai de graca."
)

assert auc < 0.99, (
    f"AUC {auc:.4f} e bom demais para ser verdade. Isso e assinatura de VAZAMENTO: "
    "alguma feature esta contando o futuro. Refaca o corte antes de confiar neste numero."
)

assert lift_top200 >= 2.5, (
    f"lift_top200 de {lift_top200:.2f}x nao paga o projeto: a fila precisa valer bem mais que ligar no aleatorio."
)

print("os tres testes passaram.")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 7 · O score dos clientes
# MAGIC
# MAGIC `predict_proba`, nunca `pyfunc.predict` -- este ultimo devolve a CLASSE e
# MAGIC transforma a coluna inteira em zero e um, o que faz a fila virar sorteio.
# MAGIC
# MAGIC Nada de `mlflow.pyfunc.spark_udf`: nao roda no serverless
# MAGIC (`InvalidVersion: '18.x-aarch64-photon-scala2'`). Para 2.816 clientes,
# MAGIC pandas e a escolha certa de qualquer forma.

# COMMAND ----------

modelo_prod = mlflow.sklearn.load_model(f"models:/{MODELO_UC}@prod")

score_pdf = spark.table(f"{catalog}.gold.features_cliente").toPandas()
referencia_score = score_pdf["_referencia"].iloc[0]

# Le a ordem das colunas do PROPRIO modelo: a ordem da tabela pode mudar sem
# aviso, e um score com colunas trocadas nao da erro -- da numero errado.
colunas = list(modelo_prod.feature_names_in_)
score_pdf["score"] = modelo_prod.predict_proba(score_pdf[colunas].astype("float64"))[:, 1]

saida = pd.DataFrame(
    {
        "cliente_id": score_pdf["cliente_id"].astype(int),
        "score": score_pdf["score"].astype(float),
        "_referencia": referencia_score,
        "versao": int(versao),
    }
)

# A FAIXA E ANCORADA NA TAXA BASE, NAO EM QUARTIL.
#
# Ela ja foi `NTILE(4) OVER (ORDER BY score)`, e o quartil mentia de duas
# maneiras ao mesmo tempo, as duas medidas:
#
#   1. "Muito quente" era o quartil de cima da base inteira, entao ia de
#      score 0,0407 a 0,9821 -- 24 vezes de diferenca sob a MESMA palavra.
#   2. A fila e o top 200 por score, logo as 200 linhas caiam dentro desse
#      quartil: `SELECT faixa, COUNT(*) FROM gold.fila_semanal GROUP BY faixa`
#      devolvia uma linha so, "Muito quente 200". A coluna era constante
#      exatamente onde o vendedor a le.
#
# Quartil responde "em que posicao ele esta"; quem vai ligar precisa de "qual e
# a chance dele". Os cortes agora sao multiplos da taxa base medida no treino
# (taxa_base = a conversao de quem liga sem modelo): 1x, 2x e 4x. A faixa passa
# a significar a mesma coisa toda semana, e nao muda de sentido porque a base
# de clientes cresceu.
#
# `vezes_base` existe para a faixa nunca aparecer sozinha: um score de 0,45
# soa baixo ate voce ler que e 4,4x a media da base. O numero e o denominador
# andam juntos ou o numero engana.
CORTES = {"Morna": 1.0, "Quente": 2.0, "Muito quente": 4.0}

spark.createDataFrame(saida).createOrReplaceTempView("_score_bruto")
spark.sql(f"""
    CREATE OR REPLACE TABLE {catalog}.gold.score_propensao AS
    SELECT cliente_id, score,
           CASE WHEN score >= {CORTES["Muito quente"] * taxa_base} THEN 'Muito quente'
                WHEN score >= {CORTES["Quente"] * taxa_base}       THEN 'Quente'
                WHEN score >= {CORTES["Morna"] * taxa_base}        THEN 'Morna'
                ELSE 'Fria' END                    AS faixa,
           ROUND(score / {taxa_base}, 2)           AS vezes_base,
           _referencia, versao, current_timestamp() AS _pontuado_em
    FROM _score_bruto
""")

print(f"gold.score_propensao: {saida.shape[0]:,} clientes pontuados na versao {versao}")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 8 · As metricas tambem viram tabela
# MAGIC
# MAGIC O Genie nao le MLflow, e daqui a seis meses ninguem abre a interface de
# MAGIC experimento. O que precisa sobreviver vira tabela da gold.

# COMMAND ----------

metricas = pd.DataFrame(
    [
        {
            "versao": int(versao),
            "auc": auc,
            "lift_top200": lift_top200,
            "acertos_top200": acertos_top200,
            "taxa_base": taxa_base,
            "auc_baseline_recencia": baselines["-recencia_dias  (ligue para quem comprou recentemente)"],
            "auc_baseline_valor": baselines["valor_total     (ligue para quem compra mais)"],
            "auc_baseline_atraso": baselines["atraso_relativo (ligue para quem esta atrasado)"],
            "melhor_baseline_auc": melhor_baseline,
            "feature_top1": feature_top1,
            "referencia_treino": referencia_treino,
        }
    ]
)
spark.createDataFrame(metricas).withColumn("_treinado_em", F.current_timestamp()).write.mode("overwrite").option(
    "overwriteSchema", "true"
).saveAsTable(f"{catalog}.gold.modelo_metricas")

# A calibragem e a prova que o comercial confere sozinho, sem saber o que e AUC:
# a taxa de compra tem que SUBIR da faixa fria para a muito quente.
holdout = pd.DataFrame({"score": modelo.predict_proba(X_te)[:, 1], "comprou": y_te.to_numpy()})
# A calibragem TEM que usar os mesmos cortes de gold.score_propensao, senao ela
# prova uma faixa que ninguem ve. Era `pd.qcut(..., 4)` -- quatro grupos do
# mesmo tamanho, que e outra coisa: media a ordenacao, nao o significado do
# rotulo. Com os cortes absolutos os grupos saem de tamanhos diferentes, e isso
# e o esperado: pouca gente mesmo tem 4x a chance media.
holdout["faixa"] = pd.cut(
    holdout["score"],
    bins=[-float("inf")]
    + [CORTES[f] * taxa_base for f in ("Morna", "Quente", "Muito quente")]
    + [float("inf")],
    labels=["Fria", "Morna", "Quente", "Muito quente"],
    right=False,
)
calibragem = (
    holdout.groupby("faixa", observed=True)
    .agg(clientes=("comprou", "size"), compraram=("comprou", "sum"), score_medio=("score", "mean"))
    .reset_index()
)
calibragem["taxa_de_compra"] = calibragem["compraram"] / calibragem["clientes"]
calibragem["faixa"] = calibragem["faixa"].astype(str)

spark.createDataFrame(calibragem).write.mode("overwrite").option("overwriteSchema", "true").saveAsTable(
    f"{catalog}.gold.calibragem_holdout"
)

print(calibragem.to_string(index=False))

# COMMAND ----------


def escapar(texto: str) -> str:
    """Aspas simples encerram o literal SQL do COMMENT -- dobrar e o escape."""
    return texto.replace("'", "''")


COMENTARIOS = {
    "score_propensao": {
        "_tabela": "Propensao de compra na proxima semana, um cliente por linha, no corte de features_cliente. Score continuo de 0 a 1 vindo de predict_proba -- nao e classe.",
        "cliente_id": "Cliente. Chave para gold.dim_cliente.",
        "score": "Probabilidade estimada de comprar nos proximos 7 dias. Contínuo: se so houver 0 e 1, foi usado predict no lugar de predict_proba.",
        "faixa": "Chance do cliente comparada com a taxa base (a conversao de quem liga sem modelo): Fria abaixo da base, Morna a partir de 1x, Quente de 2x e Muito quente de 4x. NAO e quartil -- quartil fazia as 200 linhas da fila cairem todas no mesmo rotulo.",
        "vezes_base": "Quantas vezes a chance deste cliente supera a taxa base. E o denominador da faixa: 0,45 parece pouco ate se ler 4,4x a media.",
        "_referencia": "Data de corte das features usadas para pontuar.",
        "versao": "Versao do modelo no Unity Catalog que gerou este score. E o que liga a fila ao registro.",
        "_pontuado_em": "Quando a pontuacao rodou.",
    },
    "modelo_metricas": {
        "_tabela": "Uma linha por treino do modelo de propensao. Existe porque o Genie nao le MLflow e, daqui a seis meses, ninguem abre a interface de experimento.",
        "versao": "Versao registrada no Unity Catalog.",
        "auc": "AUC no holdout de 25%. Metrica de quem treina.",
        "lift_top200": "Quantas vezes a fila de 200 supera o acaso. E a metrica que responde o diretor.",
        "acertos_top200": "Quantos dos 200 melhores compraram de fato, medido out-of-fold.",
        "taxa_base": "Fracao de clientes que compra na semana sem modelo nenhum.",
        "auc_baseline_recencia": "AUC de ordenar por -recencia_dias. Abaixo de 0,5 significa que a intuicao esta invertida.",
        "auc_baseline_valor": "AUC de ordenar por valor_total.",
        "auc_baseline_atraso": "AUC de ordenar por atraso_relativo.",
        "melhor_baseline_auc": "O melhor dos baselines. E a regua: o modelo tem que ganhar dele por pelo menos 0,05.",
        "feature_top1": "Feature nº 1 por importancia de permutacao.",
        "referencia_treino": "Data de corte do dataset de treino.",
        "_treinado_em": "Quando o treino rodou.",
    },
    "calibragem_holdout": {
        "_tabela": "Taxa de compra por faixa de score no holdout, nos MESMOS cortes de gold.score_propensao. E a prova que o comercial confere sozinho: a taxa tem que SUBIR da faixa fria para a muito quente, e o score medio previsto tem que ficar na mesma ordem de grandeza. Hoje nao bate na ponta de cima: a faixa Muito quente preve 0,69 e converte 0,49 -- o modelo ordena melhor do que estima, e por isso a receita esperada da fila e estimativa por cima.",
        "faixa": "Mesma faixa de gold.score_propensao: multiplos da taxa base, nao quartil. Grupos de tamanhos diferentes sao o esperado.",
        "clientes": "Clientes do holdout na faixa.",
        "compraram": "Quantos compraram na janela de 7 dias.",
        "score_medio": "Score medio da faixa.",
        "taxa_de_compra": "compraram / clientes. Se sobe faixa a faixa, o score ordena.",
    },
}

for tabela, comentarios in COMENTARIOS.items():
    nome = f"{catalog}.gold.{tabela}"
    spark.sql(f"COMMENT ON TABLE {nome} IS '{escapar(comentarios['_tabela'])}'")
    colunas = {c.name for c in spark.table(nome).schema.fields}
    for coluna, texto in comentarios.items():
        if coluna != "_tabela" and coluna in colunas:
            spark.sql(f"ALTER TABLE {nome} ALTER COLUMN `{coluna}` COMMENT '{escapar(texto)}'")

print("metadado aplicado nas tres tabelas.")
