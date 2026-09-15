# Databricks notebook source
# MAGIC %md
# MAGIC # Features de cliente — o que descreve um cliente
# MAGIC
# MAGIC A gold sabe tudo sobre ontem e nada sobre a semana que vem. O diretor nao
# MAGIC perguntou nada sobre o passado: ele perguntou **quais 200 ligar**.
# MAGIC
# MAGIC Tres ideias moram neste arquivo, e as tres sao a aula:
# MAGIC
# MAGIC 1. **A data de corte e a espinha.** Toda feature sai de dado ANTERIOR a
# MAGIC    uma data que entra por parametro. Nao e disciplina pessoal, e
# MAGIC    assinatura de funcao -- e vira coluna `_referencia` na tabela.
# MAGIC 2. **Uma funcao, dois usos.** A mesma `montar_features()` gera o dado de
# MAGIC    treino (com rotulo) e o de score (sem rotulo). E impossivel os dois
# MAGIC    divergirem. Esse desencontro tem nome -- *training/serving skew* -- e e
# MAGIC    o que o Feature Store resolve com infraestrutura. Aqui esta resolvido
# MAGIC    com um `def`.
# MAGIC 3. **Feature e conhecimento de negocio virando coluna.** `recencia_dias`
# MAGIC    esta em qualquer tutorial. `atraso_relativo` nao esta em nenhum, porque
# MAGIC    depende de saber que distribuicao funciona por ciclo de reposicao.

# COMMAND ----------

import datetime as dt

from pyspark.sql import DataFrame
from pyspark.sql import functions as F
from pyspark.sql.window import Window

# COMMAND ----------

dbutils.widgets.text("catalog", "lakehouse_rotaperfume", "Catalogo")
catalog = dbutils.widgets.get("catalog").strip()

if not catalog:
    raise ValueError("O parametro 'catalog' chegou vazio.")

# O "hoje" deste dataset e 2026-08-31, a ultima data de pedido da gold.
# NUNCA use current_date() aqui: o dia em que o notebook roda nao tem nada a ver
# com o dia que o dado conhece, e misturar os dois e a origem silenciosa de
# metade dos bugs de ML.
REFERENCIA_TREINO = dt.date(2026, 8, 1)
REFERENCIA_SCORE = dt.date(2026, 8, 31)

# A fila que o time ataca e SEMANAL. O rotulo tem que ter o mesmo horizonte da
# decisao -- com 30 dias a pergunta e o rotulo deixam de ser a mesma coisa.
JANELA_ALVO_DIAS = 7

print(f"corte de treino: {REFERENCIA_TREINO} | corte de score: {REFERENCIA_SCORE}")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Por que `gold.dim_cliente` nao entra em feature nenhuma
# MAGIC
# MAGIC Ela tem `dias_sem_comprar`, `receita_acumulada` e `total_pedidos` -- que
# MAGIC parecem features prontas e sao **vazamento**: foram calculadas sobre a
# MAGIC base INTEIRA, sem corte nenhum. Usar qualquer uma delas e contar para o
# MAGIC modelo o que aconteceu depois da data em que ele deveria estar decidindo.
# MAGIC
# MAGIC `dim_cliente` so volta no prompt 3, para pegar nome e cidade -- rotulo de
# MAGIC tela, nao feature.

# COMMAND ----------


def montar_features(referencia: dt.date) -> DataFrame:
    """Uma linha por cliente, com tudo que se sabia dele ATE `referencia`.

    Cada fonte e filtrada pela data dela na PRIMEIRA linha da leitura. Nao ha
    excecao, e e proposital: filtrar depois, no meio da agregacao, e como o
    vazamento entra sem ninguem ver.
    """
    corte = F.lit(referencia).cast("date")

    # ---- fontes, ja cortadas -------------------------------------------------
    vendas = spark.table(f"{catalog}.gold.fato_vendas").where(F.col("data_pedido") < corte)
    oportunidades = spark.table(f"{catalog}.silver.oportunidades").where(F.col("data_abertura") < corte)
    visitas = spark.table(f"{catalog}.silver.visitas").where(F.col("data_visita") < corte)

    # ---- RFM -----------------------------------------------------------------
    # valor_total soma `receita`, que ja entra NEGATIVA na devolucao: o cliente
    # que devolve metade do que compra nao aparece como grande comprador.
    rfm = vendas.groupBy("cliente_id").agg(
        F.datediff(corte, F.max("data_pedido")).cast("double").alias("recencia_dias"),
        F.countDistinct("pedido_id").cast("double").alias("frequencia_pedidos"),
        F.sum("receita").cast("double").alias("valor_total"),
        F.sum("margem").cast("double").alias("margem_total"),
        F.min("data_pedido").alias("_primeiro_pedido"),
        F.max("data_pedido").alias("_ultimo_pedido"),
    )
    rfm = rfm.withColumn(
        "ticket_medio",
        (F.col("valor_total") / F.nullif(F.col("frequencia_pedidos"), F.lit(0.0))).cast("double"),
    ).withColumn(
        "margem_percentual",
        (F.col("margem_total") / F.nullif(F.col("valor_total"), F.lit(0.0))).cast("double"),
    )

    # ---- Ritmo ---------------------------------------------------------------
    # O intervalo medio precisa de pelo menos DOIS pedidos. Cliente com um pedido
    # so fica NULL aqui, de proposito: inventar zero faria dele o cliente mais
    # pontual da base.
    ritmo = rfm.withColumn(
        "intervalo_medio_dias",
        (
            F.datediff(F.col("_ultimo_pedido"), F.col("_primeiro_pedido"))
            / F.nullif(F.col("frequencia_pedidos") - 1, F.lit(0.0))
        ).cast("double"),
    )

    # Desvio dos intervalos entre pedidos consecutivos, por cliente.
    pedidos = vendas.select("cliente_id", "pedido_id", "data_pedido").distinct()
    janela = Window.partitionBy("cliente_id").orderBy("data_pedido")
    intervalos = (
        pedidos.withColumn("_anterior", F.lag("data_pedido").over(janela))
        .where(F.col("_anterior").isNotNull())
        .withColumn("_gap", F.datediff(F.col("data_pedido"), F.col("_anterior")).cast("double"))
        .groupBy("cliente_id")
        .agg(F.stddev("_gap").cast("double").alias("desvio_intervalo_dias"))
    )

    recentes = (
        vendas.where(F.col("data_pedido") >= F.date_sub(corte, 90))
        .groupBy("cliente_id")
        .agg(F.countDistinct("pedido_id").cast("double").alias("pedidos_ultimos_90d"))
    )

    # ---- CRM -----------------------------------------------------------------
    crm = oportunidades.groupBy("cliente_id").agg(
        F.sum(F.when(~F.col("fechada"), 1).otherwise(0)).cast("double").alias("oportunidades_abertas"),
        F.sum(F.when(F.col("ganha"), 1).otherwise(0)).cast("double").alias("oportunidades_ganhas"),
        F.count("*").cast("double").alias("_oportunidades_total"),
    )
    crm = crm.withColumn(
        "taxa_ganho",
        (F.col("oportunidades_ganhas") / F.nullif(F.col("_oportunidades_total"), F.lit(0.0))).cast("double"),
    ).drop("_oportunidades_total")

    visitas_90d = (
        visitas.where(F.col("data_visita") >= F.date_sub(corte, 90))
        .groupBy("cliente_id")
        .agg(F.count("*").cast("double").alias("visitas_90d"))
    )
    conversao = visitas.groupBy("cliente_id").agg(
        (F.sum(F.when(F.col("gerou_pedido"), 1).otherwise(0)) / F.nullif(F.count("*"), F.lit(0)))
        .cast("double")
        .alias("conversao_visita")
    )

    # ---- Mix -----------------------------------------------------------------
    mix = vendas.groupBy("cliente_id").agg(
        F.countDistinct("sku").cast("double").alias("skus_distintos"),
        F.countDistinct("categoria").cast("double").alias("categorias_distintas"),
    )

    por_marca = vendas.groupBy("cliente_id", "marca").agg(F.sum("receita").alias("_receita_marca"))
    marca_top = por_marca.groupBy("cliente_id").agg(F.max("_receita_marca").cast("double").alias("_receita_marca_top"))

    # Unico join necessario: saber quais SKUs sao lancamento na data de corte.
    lancamentos = (
        spark.table(f"{catalog}.gold.dim_produto")
        .where(F.col("data_lancamento").isNotNull())
        .where(F.col("data_lancamento") >= F.date_sub(corte, 120))
        .where(F.col("data_lancamento") < corte)
        .select("sku")
    )
    comprou_lancamento = (
        vendas.join(lancamentos, on="sku", how="inner")
        .select("cliente_id")
        .distinct()
        .withColumn("comprou_lancamento", F.lit(1.0))
    )

    # ---- junta tudo ----------------------------------------------------------
    features = (
        ritmo.join(intervalos, "cliente_id", "left")
        .join(recentes, "cliente_id", "left")
        .join(crm, "cliente_id", "left")
        .join(visitas_90d, "cliente_id", "left")
        .join(conversao, "cliente_id", "left")
        .join(mix, "cliente_id", "left")
        .join(marca_top, "cliente_id", "left")
        .join(comprou_lancamento, "cliente_id", "left")
    )

    # Teto em 10: cliente com intervalo de 2 dias que sumiu ha 6 meses geraria um
    # numero de tres digitos que domina o modelo sem dizer nada de novo.
    #
    # NAO use F.least(razao, 10) aqui: o least do Spark IGNORA nulo, entao
    # least(NULL, 10) devolve 10 -- e os 105 clientes de pedido unico, sobre os
    # quais nao sabemos ritmo NENHUM, iriam para o topo da fila com alarme
    # maximo. O when/otherwise abaixo propaga o nulo, que e a resposta honesta.
    razao_atraso = F.col("recencia_dias") / F.nullif(F.col("intervalo_medio_dias"), F.lit(0.0))
    features = features.withColumn(
        "atraso_relativo",
        F.when(razao_atraso > F.lit(10.0), F.lit(10.0)).otherwise(razao_atraso).cast("double"),
    ).withColumn(
        "concentracao_marca_top",
        (F.col("_receita_marca_top") / F.nullif(F.col("valor_total"), F.lit(0.0))).cast("double"),
    )

    # Ausencia de CRM e ausencia de fato, nao dado faltando: vira 0.
    # As features de RITMO ficam NULL de proposito -- ver comentario acima.
    zeros = [
        "pedidos_ultimos_90d",
        "oportunidades_abertas",
        "oportunidades_ganhas",
        "taxa_ganho",
        "visitas_90d",
        "conversao_visita",
        "comprou_lancamento",
    ]
    features = features.fillna(0.0, subset=zeros)

    return features.select(
        "cliente_id",
        # RFM
        "recencia_dias",
        "frequencia_pedidos",
        "valor_total",
        "ticket_medio",
        "margem_total",
        "margem_percentual",
        # Ritmo
        "intervalo_medio_dias",
        "desvio_intervalo_dias",
        "atraso_relativo",
        "pedidos_ultimos_90d",
        # CRM
        "oportunidades_abertas",
        "oportunidades_ganhas",
        "taxa_ganho",
        "visitas_90d",
        "conversao_visita",
        # Mix
        "skus_distintos",
        "categorias_distintas",
        "concentracao_marca_top",
        "comprou_lancamento",
        F.lit(referencia).cast("date").alias("_referencia"),
    )


# COMMAND ----------

# MAGIC %md
# MAGIC ## As duas tabelas, da mesma funcao
# MAGIC
# MAGIC A unica diferenca entre treino e score e a data e o rotulo. Nenhuma linha
# MAGIC de calculo de feature e escrita duas vezes.

# COMMAND ----------

# --- treino: corte em 01/08, mais o alvo da semana seguinte -------------------
features_treino = montar_features(REFERENCIA_TREINO)

fim_janela = REFERENCIA_TREINO + dt.timedelta(days=JANELA_ALVO_DIAS - 1)
compradores = (
    spark.table(f"{catalog}.gold.fato_vendas")
    .where(F.col("data_pedido").between(F.lit(REFERENCIA_TREINO), F.lit(fim_janela)))
    .select("cliente_id")
    .distinct()
    .withColumn("comprou_em_7d", F.lit(1))
)

treino = features_treino.join(compradores, "cliente_id", "left").fillna(0, subset=["comprou_em_7d"])

treino.write.mode("overwrite").option("overwriteSchema", "true").saveAsTable(f"{catalog}.gold.features_treino")

# --- score: corte em 31/08, sem alvo -----------------------------------------
montar_features(REFERENCIA_SCORE).write.mode("overwrite").option("overwriteSchema", "true").saveAsTable(
    f"{catalog}.gold.features_cliente"
)

print("features_treino e features_cliente gravadas.")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Metadado
# MAGIC
# MAGIC Comentario em portugues na tabela e em toda coluna. Coluna de feature sem
# MAGIC comentario e coluna que alguem vai usar errado daqui a tres meses -- e o
# MAGIC que o modelo aprende ninguem consegue adivinhar pelo nome.

# COMMAND ----------

COMENTARIOS = {
    "cliente_id": "Cliente. Chave para gold.dim_cliente.",
    "recencia_dias": "Dias entre a data de corte e o ultimo pedido. Sozinha, ordena a fila PIOR que o acaso: quem sumiu ha mais tempo costuma ter sumido de vez.",
    "frequencia_pedidos": "Pedidos distintos ate a data de corte.",
    "valor_total": "Receita acumulada ate o corte. Devolucao entra negativa, entao quem devolve muito nao aparece como grande comprador.",
    "ticket_medio": "Receita dividida por pedidos distintos.",
    "margem_total": "Margem acumulada ate o corte.",
    "margem_percentual": "Margem sobre receita. Separa o cliente que compra muito do cliente que da lucro.",
    "intervalo_medio_dias": "Dias medios entre o primeiro e o ultimo pedido, por pedido. NULL para cliente com um pedido so -- inventar zero faria dele o mais pontual da base.",
    "desvio_intervalo_dias": "Desvio padrao dos intervalos entre pedidos consecutivos. Alto = cliente irregular. NULL para quem tem menos de tres pedidos.",
    "atraso_relativo": "Recencia dividida pelo intervalo medio, com teto em 10. E a feature da noite: 20 dias sem comprar e normal para quem compra a cada 30 e e alarme para quem compra a cada 7.",
    "pedidos_ultimos_90d": "Pedidos distintos nos 90 dias antes do corte.",
    "oportunidades_abertas": "Oportunidades ainda nao fechadas na data de corte.",
    "oportunidades_ganhas": "Oportunidades marcadas como 'Fechado ganho'.",
    "taxa_ganho": "Ganhas sobre o total de oportunidades. Zero para quem nunca teve oportunidade.",
    "visitas_90d": "Visitas comerciais nos 90 dias antes do corte.",
    "conversao_visita": "Visitas que geraram pedido sobre o total de visitas.",
    "skus_distintos": "SKUs diferentes ja comprados.",
    "categorias_distintas": "Categorias diferentes ja compradas. Mede amplitude do relacionamento.",
    "concentracao_marca_top": "Receita da marca preferida sobre a receita total. Perto de 1 = cliente de marca unica, mais facil de perder para um concorrente dessa marca.",
    "comprou_lancamento": "1 se comprou algum SKU lancado nos 120 dias antes do corte. Esparsa por natureza: poucos produtos tem data de lancamento preenchida.",
    "comprou_em_7d": "ALVO. 1 se o cliente fez pedido nos 7 dias a partir da data de corte. A janela e semanal porque a fila que o time ataca e semanal.",
    "_referencia": "Data de corte usada para calcular TODAS as colunas desta linha. Nao e comentario no codigo: e coluna na tabela.",
}

DESCRICAO = {
    "features_treino": "Features de cliente no corte de 2026-08-01, com o alvo comprou_em_7d. Gerada pela MESMA funcao que features_cliente -- e o que torna o training/serving skew impossivel.",
    "features_cliente": "Features de cliente no corte de 2026-08-31, sem alvo. E o dataset que vai ser pontuado.",
}


def escapar(texto: str) -> str:
    """Escapa aspas simples para o literal SQL do COMMENT."""
    return texto.replace("'", "''")


for tabela, descricao in DESCRICAO.items():
    nome = f"{catalog}.gold.{tabela}"
    # Aspas simples dentro do texto (ex.: 'Fechado ganho') encerram o literal SQL
    # e viram PARSE_SYNTAX_ERROR. Dobrar e o escape do SQL padrao.
    spark.sql(f"COMMENT ON TABLE {nome} IS '{escapar(descricao)}'")
    colunas = {c.name for c in spark.table(nome).schema.fields}
    for coluna, texto in COMENTARIOS.items():
        if coluna in colunas:
            spark.sql(f"ALTER TABLE {nome} ALTER COLUMN `{coluna}` COMMENT '{escapar(texto)}'")

print("metadado aplicado nas duas tabelas.")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Conferencia de sanidade
# MAGIC
# MAGIC Recencia negativa e a assinatura do vazamento: significa que uma fonte
# MAGIC escapou do filtro e o cliente "comprou depois do corte".

# COMMAND ----------

for tabela in ("features_treino", "features_cliente"):
    df = spark.table(f"{catalog}.gold.{tabela}")
    menor = df.agg(F.min("recencia_dias")).collect()[0][0]
    print(f"{tabela}: {df.count():,} clientes | corte {df.select('_referencia').first()[0]} | menor recencia {menor}")
    if menor is not None and menor < 0:
        raise RuntimeError(
            f"VAZAMENTO em {tabela}: recencia_dias negativa ({menor}). "
            "Alguma fonte nao foi filtrada por data antes de agregar."
        )

alvo = (
    spark.table(f"{catalog}.gold.features_treino")
    .agg(
        F.count("*").alias("clientes"),
        F.sum("comprou_em_7d").alias("compraram"),
        F.round(100 * F.avg("comprou_em_7d"), 2).alias("taxa_base_pct"),
    )
    .collect()[0]
)

print(
    f"\nTAXA BASE: {alvo['compraram']:,} de {alvo['clientes']:,} clientes "
    f"= {alvo['taxa_base_pct']}%  -- de cada 200 ligacoes as cegas, "
    f"{round(2 * alvo['taxa_base_pct'])} viram pedido."
)
