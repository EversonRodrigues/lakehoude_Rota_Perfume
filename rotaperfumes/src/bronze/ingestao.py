# Databricks notebook source
# MAGIC %md
# MAGIC # Bronze: o arquivo vira tabela
# MAGIC
# MAGIC Raw e arquivo; bronze e tabela. Aqui cada CSV do Volume vira uma tabela
# MAGIC do Unity Catalog -- que responde `SELECT`, aparece na linhagem e tem
# MAGIC coluna com nome.
# MAGIC
# MAGIC **Tudo entra como STRING, de proposito.** Bronze e o dado como ele
# MAGIC chegou: o `cnpj` continua com os espacos que o CRM mandou, `ativo`
# MAGIC continua `S`/`N`, data vazia continua vazia. Conserto disso e silver.
# MAGIC
# MAGIC **E a conta tem que fechar.** Se a conferencia de chegada (entrega 1)
# MAGIC registrou N linhas para um arquivo, a tabela bronze tem que ter N linhas.
# MAGIC Tabela com linha faltando nao da erro: ela responde `SELECT` do mesmo
# MAGIC jeito, so que com o numero errado.

# COMMAND ----------

from datetime import datetime, timezone

from pyspark.sql import Row
from pyspark.sql import functions as F
from pyspark.sql.utils import AnalysisException

# COMMAND ----------

dbutils.widgets.text("catalog", "lakehouse_rotaperfume", "Catalogo")
catalog = dbutils.widgets.get("catalog").strip()

if not catalog:
    raise ValueError("O parametro 'catalog' chegou vazio.")

RAIZ_RAW = f"/Volumes/{catalog}/bronze/raw"
TABELA_CHEGADA = f"{catalog}.bronze._raw_arquivos"
TABELA_CARGA = f"{catalog}.bronze._bronze_carga"

# A mesma lista de src/raw/conferencia.py. Se um arquivo novo entrar no projeto,
# ele entra nas duas -- a conferencia cobra a chegada, esta aqui cobra a carga.
ESPERADOS = {
    "erp": ["produtos", "pedidos", "itens_pedido", "pagamentos", "estoque"],
    "crm": ["clientes", "vendedores", "carteira", "oportunidades", "visitas"],
}

# COMMAND ----------

# MAGIC %md
# MAGIC ## A fonte da verdade e a entrega 1
# MAGIC
# MAGIC `bronze._raw_arquivos` diz quantas linhas de dado chegaram em cada
# MAGIC arquivo. Ela deixa de ser "aquela tarefa chata da noite passada" e vira o
# MAGIC numero que a bronze tem que respeitar.

# COMMAND ----------

try:
    esperado_por_arquivo = {
        (linha["sistema"], linha["arquivo"]): linha["linhas"] for linha in spark.table(TABELA_CHEGADA).collect()
    }
except AnalysisException as erro:
    raise RuntimeError(
        f"Nao encontrei {TABELA_CHEGADA}. A tarefa raw_conferencia (entrega 1) precisa rodar antes desta."
    ) from erro

print(f"{TABELA_CHEGADA}: {len(esperado_por_arquivo)} arquivo(s) conferido(s) na chegada.")

# COMMAND ----------


def ler_csv_como_string(caminho: str):
    """Le o CSV sem inferir nada: toda coluna vira STRING.

    `mode=FAILFAST` para que linha malformada exploda aqui, alto, em vez de
    virar NULL silencioso la na frente.
    """
    return spark.read.option("header", "true").option("inferSchema", "false").option("mode", "FAILFAST").csv(caminho)


# COMMAND ----------

ingerido_em = datetime.now(timezone.utc)
carga: list[Row] = []
divergencias: list[str] = []

for sistema, arquivos in ESPERADOS.items():
    for nome in arquivos:
        origem = f"{RAIZ_RAW}/{sistema}/{nome}.csv"
        destino = f"{catalog}.bronze.{nome}"

        df = (
            ler_csv_como_string(origem)
            .withColumn("_arquivo_origem", F.col("_metadata.file_path"))
            .withColumn("_ingerido_em", F.lit(ingerido_em).cast("timestamp"))
        )

        df.write.mode("overwrite").option("overwriteSchema", "true").saveAsTable(destino)

        spark.sql(
            f"COMMENT ON TABLE {destino} IS "
            f"'Bronze: {sistema}/{nome}.csv como ele chegou ao Volume, toda coluna STRING. "
            f"Sem regra de negocio, sem limpeza -- isso e silver.'"
        )

        gravadas = spark.table(destino).count()
        esperadas = esperado_por_arquivo.get((sistema, f"{nome}.csv"))

        if esperadas is None:
            divergencias.append(f"{sistema}/{nome}.csv: nao foi conferido na chegada (ausente em {TABELA_CHEGADA})")
        elif gravadas != esperadas:
            divergencias.append(f"{sistema}/{nome}: esperado {esperadas:,} linhas, gravado {gravadas:,}")

        carga.append(
            Row(
                sistema=sistema,
                tabela=nome,
                linhas_esperadas=int(esperadas) if esperadas is not None else None,
                linhas_gravadas=int(gravadas),
                ingerido_em=ingerido_em,
            )
        )
        marca = "ok " if esperadas == gravadas else "!! "
        print(f"  {marca} bronze.{nome:<16} {gravadas:>9,} linhas")

# COMMAND ----------

# MAGIC %md
# MAGIC Registra a carga **antes** de decidir se falha: mesmo numa execucao que
# MAGIC quebra, fica gravado o que foi carregado e o quanto divergiu.

# COMMAND ----------

(
    spark.createDataFrame(carga)
    .select("sistema", "tabela", "linhas_esperadas", "linhas_gravadas", "ingerido_em")
    .write.mode("overwrite")
    .option("overwriteSchema", "true")
    .saveAsTable(TABELA_CARGA)
)

spark.sql(
    f"COMMENT ON TABLE {TABELA_CARGA} IS "
    "'Carga da bronze: uma linha por tabela, com o numero de linhas que a conferencia de chegada "
    "esperava e o que de fato foi gravado. Reescrita a cada execucao do job.'"
)

# COMMAND ----------

if divergencias:
    detalhe = "\n  - ".join(divergencias)
    raise RuntimeError(
        f"A bronze nao fecha com a conferencia de chegada -- {len(divergencias)} divergencia(s):\n  - {detalhe}\n\n"
        "Tabela com linha faltando nao levanta erro sozinha: ela responde SELECT normalmente, "
        "so que com o numero errado."
    )

# COMMAND ----------

resumo = spark.table(TABELA_CARGA).orderBy(F.col("linhas_gravadas").desc())
resumo.show(truncate=False)

totais = resumo.agg(
    F.count("*").alias("tabelas"),
    F.sum("linhas_gravadas").alias("linhas"),
).collect()[0]

print(f"\n{totais['tabelas']} tabelas | {totais['linhas']:,} linhas | a conta fecha com {TABELA_CHEGADA}")
