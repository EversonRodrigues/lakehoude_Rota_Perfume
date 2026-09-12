# Databricks notebook source
# MAGIC %md
# MAGIC # Conferencia de chegada do raw
# MAGIC
# MAGIC A tarefa mais chata do pipeline, e a que mais salva emprego.
# MAGIC
# MAGIC O erro mais caro de pipeline nao e o que quebra -- e o arquivo que nao
# MAGIC chegou e ninguem viu. Ele nao levanta excecao sozinho: ele da um numero
# MAGIC menor, e o dashboard mostra metade da receita com cara de numero certo.
# MAGIC
# MAGIC Este notebook confere que os 10 arquivos existem no Volume e nao estao
# MAGIC vazios, registra o que chegou em `bronze._raw_arquivos` e **falha o job**
# MAGIC se algo estiver faltando.

# COMMAND ----------

from datetime import datetime, timezone

from pyspark.sql import Row
from pyspark.sql import functions as F

# COMMAND ----------

dbutils.widgets.text("catalog", "lakehouse_rotaperfume", "Catalogo")
catalog = dbutils.widgets.get("catalog").strip()

if not catalog:
    raise ValueError("O parametro 'catalog' chegou vazio.")

RAIZ_RAW = f"/Volumes/{catalog}/bronze/raw"
TABELA_CONTROLE = f"{catalog}.bronze._raw_arquivos"

# Os 10 arquivos que a noite espera. Se um dia a lista crescer, ela cresce aqui
# -- e o job passa a falhar enquanto o arquivo novo nao chegar.
ESPERADOS = {
    "erp": ["produtos", "pedidos", "itens_pedido", "pagamentos", "estoque"],
    "crm": ["clientes", "vendedores", "carteira", "oportunidades", "visitas"],
}

print(f"Conferindo {sum(len(v) for v in ESPERADOS.values())} arquivos em {RAIZ_RAW}")

# COMMAND ----------


def listar_volume(sistema: str) -> dict[str, int]:
    """Nome do arquivo -> tamanho em bytes, para uma pasta do Volume.

    Se a propria pasta nao existir, devolve vazio: quem reclama e a conferencia
    abaixo, com uma mensagem que diz qual arquivo faltou.
    """
    try:
        return {f.name: f.size for f in dbutils.fs.ls(f"{RAIZ_RAW}/{sistema}")}
    except Exception as erro:  # noqa: BLE001 - pasta ausente e um caso esperado
        print(f"[aviso] nao consegui listar {RAIZ_RAW}/{sistema}: {erro}")
        return {}


def contar_linhas_de_dado(caminho: str) -> int:
    """Linhas de dado do CSV, ou seja, sem contar o cabecalho."""
    return max(spark.read.text(caminho).count() - 1, 0)


# COMMAND ----------

conferido_em = datetime.now(timezone.utc)
registros: list[Row] = []
problemas: list[str] = []

for sistema, arquivos in ESPERADOS.items():
    presentes = listar_volume(sistema)

    for arquivo in arquivos:
        nome = f"{arquivo}.csv"
        caminho = f"{RAIZ_RAW}/{sistema}/{nome}"

        if nome not in presentes:
            problemas.append(f"FALTANDO: {sistema}/{nome}")
            continue

        tamanho = presentes[nome]
        if tamanho == 0:
            problemas.append(f"VAZIO (0 bytes): {sistema}/{nome}")
            continue

        linhas = contar_linhas_de_dado(caminho)
        if linhas == 0:
            problemas.append(f"SEM LINHA DE DADO (so cabecalho): {sistema}/{nome}")
            continue

        registros.append(
            Row(
                sistema=sistema,
                arquivo=nome,
                bytes=int(tamanho),
                linhas=int(linhas),
                conferido_em=conferido_em,
            )
        )
        print(f"  ok  {sistema}/{nome:<20} {tamanho:>10,} bytes  {linhas:>9,} linhas")

# COMMAND ----------

# MAGIC %md
# MAGIC Grava o que chegou **antes** de decidir se falha: mesmo numa execucao que
# MAGIC quebra, fica registrado o que estava la no momento da conferencia.

# COMMAND ----------

if registros:
    (
        spark.createDataFrame(registros)
        .select("sistema", "arquivo", "bytes", "linhas", "conferido_em")
        .write.mode("overwrite")
        .option("overwriteSchema", "true")
        .saveAsTable(TABELA_CONTROLE)
    )

    spark.sql(
        f"COMMENT ON TABLE {TABELA_CONTROLE} IS "
        "'Conferencia de chegada do raw: um registro por arquivo encontrado no Volume, "
        "com tamanho e numero de linhas de dado. Reescrita a cada execucao do job.'"
    )
    print(f"\n{TABELA_CONTROLE} atualizada com {len(registros)} arquivo(s).")

# COMMAND ----------

if problemas:
    detalhe = "\n  - ".join(problemas)
    raise RuntimeError(
        f"Conferencia de chegada falhou -- {len(problemas)} problema(s) em {RAIZ_RAW}:\n  - {detalhe}\n\n"
        "Sem esta tarefa o pipeline seguiria verde, a bronze teria menos tabelas "
        "e o dashboard mostraria um faturamento menor -- com cara de numero certo."
    )

# COMMAND ----------

resumo = spark.table(TABELA_CONTROLE).orderBy(F.col("linhas").desc())
resumo.show(truncate=False)

totais = resumo.agg(
    F.count("*").alias("arquivos"),
    F.sum("linhas").alias("linhas_de_dado"),
    F.round(F.sum("bytes") / 1024 / 1024, 1).alias("mb"),
).collect()[0]

print(f"\n{totais['arquivos']} arquivos | {totais['linhas_de_dado']:,} linhas de dado | {totais['mb']} MB")
