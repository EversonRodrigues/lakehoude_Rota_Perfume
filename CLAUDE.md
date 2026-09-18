# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A teaching project that builds a Databricks lakehouse for a fictional perfume
distributor ("Rota Perfume") out of 10 flat CSVs, across six deliverables. Three
parts:

- `dados/` — the raw source data, split by source system: `erp/` (produtos,
  pedidos, itens_pedido, pagamentos, estoque) and `crm/` (clientes, vendedores,
  carteira, oportunidades, visitas). 313,551 data rows, 14,700,966 bytes;
  `itens_pedido.csv` is the big one (197,724 rows), `vendedores.csv` the small
  one (42). These files are the local stand-in for the ERP/CRM exports — they get
  uploaded to a Unity Catalog Volume, not read from disk by jobs.
- `rotaperfumes/` — **the Declarative Automation Bundle (DAB)** that holds the
  catalog, the 15-task job and the dashboard. All bundle/`uv`/`pytest` commands
  must be run from inside this directory, never the repo root.
- `rotaperfume-direcao/` — **a Databricks App (AppKit: Node/TypeScript/React),
  not a bundle.** Night 4's second deliverable: the 200-call queue on screen for
  the sales director, with the `Rota Perfume · Direção` Genie embedded. It has
  its **own deploy cycle** — `databricks apps deploy -t default`, target
  `default`, never `dev` — and is **not** part of `rotaperfumes/`'s
  `bundle deploy`. Running `bundle deploy` on it would create the app stopped,
  with `no_compute` and no URL. Node commands (`npm run typegen`, `lint`,
  `typecheck`) run from inside this directory.
- `prompts/` — the course scripts, one directory per night
  (`noite-2-engenharia-de-dados/`, `noite-3-machine-learning/`,
  `noite-4-genie-e-app/`), indexed by `prompts/README.md`. Read the matching one
  before extending anything; they carry the target architecture and the pitfalls
  learned the hard way. Written in Portuguese, as is the domain vocabulary
  throughout the data and the code. **Workspace identity in them is replaced by
  the markers `<PERFIL>`, `<WAREHOUSE_ID>`, `<HOST_DO_WORKSPACE>`, `<SEU_EMAIL>`**
  — never substitute a real value back into a committed file.
- `README.md` — the public walkthrough of the whole project. Keep it honest when
  a command or a number changes.

## No workspace identity in this repo — how config works

There is exactly one bundle (`rotaperfumes/`) plus the app
(`rotaperfume-direcao/`), and **neither carries a workspace host, an e-mail or a
warehouse id**. Two mechanisms replace them, and both are load-bearing:

- **The host comes from `--profile`**, read from `~/.databrickscfg`, which is
  outside the repo. `workspace.host` is resolved *before* bundle variables (it is
  auth config), so `${var.something}` there fails with
  `invalid character "{" in host name`. That is why every command in this project
  passes `--profile <name>` explicitly — never rely on default resolution.
- **Everything else is a bundle variable with no default**, filled in
  `.databricks/bundle/<target>/variable-overrides.json`, which `.gitignore`
  excludes. `rotaperfumes/` needs `workspace_user` + `warehouse_id`;
  `rotaperfume-direcao/` needs `sql_warehouse_id` + `genie_space_id` +
  `genie_space_name`. Templates live at `variable-overrides.exemplo.json` in each
  directory, and are created by `.\scripts\configurar.ps1` (bundle) and
  `npm run configurar` (app).

**No default on those variables is deliberate.** A default would be somebody's
real e-mail, and a wrong one deploys into another person's workspace. Missing
values fail loudly at `bundle validate`, naming the variable.

**When adding a resource, never hard-code an id.** Use `${var.warehouse_id}` /
`${var.workspace_user}`; every existing resource already does.

The workspace this checkout is wired to belongs to the course author's account,
which is why `workspace_user` in the local override file is not the current
user's e-mail — that is correct, not a leftover.

## Current state — nights 1 to 4 (prompt 1) are done in `rotaperfumes/`

Built and verified end-to-end against the `rotaperfumes` workspace. Each
deliverable has a course script in `prompts/noite-N-*/` — see `prompts/README.md` for the index.

- `resources/catalogo.yml` — schemas `bronze`/`silver`/`gold` + MANAGED volume
  `bronze.raw`, all with `COMMENT`s
- `resources/pipeline.job.yml` — job `rotaperfume_pipeline`, serverless, daily
  06:00 `America/Sao_Paulo`. The header comment maps all six deliverables onto
  tasks — keep it honest as tasks land.
- `src/raw/conferencia.py` (task `raw_conferencia`) — the arrival check: asserts
  all 10 files exist and are non-empty, writes `(sistema, arquivo, bytes, linhas,
  conferido_em)` into `bronze._raw_arquivos`, and **raises** if anything is
  missing. A missing file doesn't error on its own — it just produces a smaller
  number that looks correct.
- `src/bronze/ingestao.py` (task `bronze_ingestao`, `depends_on`
  `raw_conferencia`) — reads the 10 CSVs into 10 bronze tables, **every column
  STRING**, plus `_arquivo_origem` / `_ingerido_em`, `overwrite` so reruns are
  idempotent. Then **reconciles**: each table's row count against
  `_raw_arquivos.linhas`, recorded in `bronze._bronze_carga`, raising on any
  mismatch. 313,551 rows across the 10 tables, zero divergence.

**Know the limit of that reconciliation before relying on it.** It compares the
Volume to bronze *within one run*, so it catches rows lost on the read path — not
a file that arrived short. Verified: truncating `pagamentos.csv` to 100 rows and
running the full job finishes **green**, because `raw_conferencia` rewrites
`_raw_arquivos` from the same truncated file (`esperadas=100, gravadas=100`)
while the total silently drops to 285,879. Catching that needs a baseline across
runs — scoped to the quality deliverable, not built yet. To see the check
actually fire, change the Volume and run the second task alone:
`databricks jobs run-now <job_id> --json '{"only":["bronze_ingestao"]}'`.
- `scripts/criar-catalogo.ps1`, `scripts/subir-raw.ps1` — PowerShell, profile as
  the first positional parameter, no default.

- `src/silver/0{1..4}-*.sql` (tasks `silver_clientes`, `silver_pedidos`,
  `silver_itens_produtos`, `silver_crm_financeiro`) — four `sql_task`s that all
  `depends_on` `bronze_ingestao` and **run in parallel**, producing the 10 silver
  tables. Each file ends with `ALTER TABLE … ADD CONSTRAINT`, so the rule belongs
  to the table, not the script. `CREATE OR REPLACE TABLE` clears constraints, so
  re-adding every run is idempotent.
- `src/gold/0{5..8}-*.sql` (tasks `gold_dimensoes` → `gold_fato_vendas` →
  `gold_marts` → `testes`) — **chained**, unlike the parallel silver tasks. Four
  conformed dimensions, `fato_vendas` at **item-of-order grain** (191,080 rows),
  three marts over that one fact, and 9 tests. The gold reads **only from
  silver**, never bronze. **15 tasks total in the job** after night 4.
- `src/ml/09-features.py` (task `ml_features`, `depends_on` `testes`) — night 3's
  first deliverable. One `montar_features(referencia)` builds 20 features per
  client from data strictly **before** a cutoff date passed as a parameter, and
  is called twice: `gold.features_treino` (cutoff 2026-08-01, plus the
  `comprou_em_7d` label) and `gold.features_cliente` (cutoff 2026-08-31, no
  label). One function for train and score is what makes training/serving skew
  impossible. Measured: **2,815 / 2,816 clients, base rate 10.12%** (285 buyers
  in the 7-day window).
- `src/ml/10-modelo.py` (task `ml_modelo`, `depends_on` `ml_features`) — measures
  the simple-rule baselines **before** training, fits a
  `HistGradientBoostingClassifier`, registers it at
  `gold.propensao_compra` in Unity Catalog with alias `@prod`, and writes
  `gold.score_propensao`, `gold.modelo_metricas`, `gold.calibragem_holdout`.
  Measured: AUC **0.8816**, `lift_top200` **4.15×**, **84** of the top 200 bought
  against 20 at random. Three `assert`s stop the task — including `auc < 0.99`,
  because leakage arrives as praise, not as an error.
- `src/ml/11-fila.sql` (task `ml_fila`, `depends_on` `ml_modelo`) — the last mile:
  `gold.fila_semanal` (200 calls with name, a Portuguese `motivo` and what to
  offer), four SQL functions in UC that the agent calls
  (`priorizar_carteira`, `contexto_cliente`, `sugerir_produtos`,
  `checar_disponibilidade`), and three `raise_error` tests. Plus
  `resources/genie-comercial.json`, the Genie Space payload.
- `resources/dashboard-comercial.lvdash.json` + `resources/dashboard.dashboard.yml`
  (resource `dashboards.comercial`) — the AI/BI dashboard **as code**, deployed by
  the bundle, not clicked. 14 widgets over a **single** dataset `ds_vendas`, with
  the KPIs declared once as dataset `columns` and referenced via
  ``MEASURE(`Receita`)``.
- `src/gold/12-retorno-ligacao.sql` (task `gold_retorno_ligacao`, `depends_on`
  `gold_marts`) — night 4's first deliverable, the **return path**. Three nights
  built the way out (file → model → the 200 calls) and the pipeline never learned
  what happened next. `gold.retorno_ligacao` is the only table in the project fed
  by the *team* rather than the pipeline, which is why it is the only
  `CREATE TABLE IF NOT EXISTS` — a redeploy must not erase what a salesperson
  answered. It is born **empty**, and empty is the correct state. It hangs off
  `gold_marts`, not off the ML block, so the app still has its table on a day the
  model fails.
- `src/gold/13-auditoria-metadado.sql` (task `auditoria_de_metadado`, **last in
  the DAG**) — raises if any gold table or column has no `COMMENT`, naming
  `tabela.coluna` in the error. Landing it required backfilling **65 missing
  column comments** across `05`, `06`, `07` and `11`.
- `resources/genie-direcao.genie_space.yml` + `resources/direcao.geniespace.json`
  (resource `genie_spaces.genie_direcao`) — the **second** Genie space,
  `Rota Perfume · Direção`, deployed by the bundle. Same model, same data as the
  comercial one; what differs is the audience, and the audience lives in ~20
  lines of business instruction under Git. Five sources (`fila_semanal`,
  `score_propensao`, `modelo_metricas`, `retorno_ligacao`, `dim_cliente`), five
  sample questions, five validated question→SQL pairs, one `text_instructions`.
  Its hard rules: expected queue revenue is `SUM(score * ticket_medio)` and is an
  **estimate**; the director's metric is `lift_top200` and it must **never** cite
  AUC; zero returns means "nobody has registered one yet", never the queue used
  as if it were a result.
- `rotaperfume-direcao/` — night 4's **second** deliverable, the app. Scaffolded
  with `databricks apps init --features analytics,genie` (AppKit 0.57.0). Two
  screens: `A semana` (four KPI cards + vendor filter + the 200-row queue) and
  `Perguntar` (the Genie space embedded, with the signed-in e-mail from
  `GET /api/quem-sou` and a permanent AI-disclosure note). Four queries in
  `config/queries/`: `kpis_semana`, `vendedores`, `fila`, `acompanhamento`.
  Measured live: **200 contacts, 36 sellers, R$ 556.423,71 expected, 4,15× lift,
  84/200, 0 returns**. First deploy **4m27s**, redeploy **1m19s**.
- **Night 4's third deliverable closed the loop**: a third screen
  `Acompanhamento` (`/acompanhamento`, reading `acompanhamento.sql`) and the
  app's **only write path** —
  `POST /api/retorno` in `server/server.ts`. Verified end to end: an invalid
  `status` is refused with **400** and never reaches the warehouse; a valid body
  writes the row; the Genie space then answered *"2 ligações registradas, 1
  virou pedido"* where minutes earlier it said nobody had registered anything —
  **with no Genie code changed at all**. Test rows deleted afterwards; the table
  is back to 0, which is the correct starting state.

The `Acompanhamento` screen was later reworked into the director's read of the
week. `acompanhamento.sql` now also carries `receita_fechada` / `receita_aberta`
/ `receita_esperada` (`SUM(ticket_medio)` by outcome — an **estimate**, the
historical average, never the invoiced order) and `ultimo_retorno_em` for
freshness. The screen shows four KPI cards (cobertura da fila, conversão real,
pedidos fechados, vendedores em campo), an outcome strip over the four statuses,
and the chart. Two honesty rules are coded in, not optional:

- **The conversion's denominator is `trabalhados`, never the 200-row queue** —
  the card says so out loud. Dividing by the queue reports a coverage problem as
  a model problem.
- **The realized lift is hidden below 30 worked calls** (`AMOSTRA_MINIMA`), which
  is what the card explains in place of a number. One sale in five calls reads as
  "2× the model" and the next return erases it.

`Kpi` / `KpisEsqueleto` live in `client/src/components/Kpi.tsx`, shared by
`SemanaPage` and `AcompanhamentoPage`. The `Kpi` contract is four parts —
value, comparison, optional highlight, **provenance** — because a number with no
denominator and no source is how a whole meeting ends up arguing the wrong thing.

**Read and write take deliberately different paths.** Every read is a typed
`.sql` file under `config/queries/`; no route runs a `SELECT`. The single write
is a `POST` whose value set is **closed by a Zod enum on the server**
(`vendeu | vai_pensar | sem_interesse | nao_atendeu`) — the button is interface,
the enum is the contract, and it is what stops the column from collecting
"vendeu", "Vendeu" and "vendido". Three rules that are easy to get wrong:

- **Never write through `appkit.analytics.query()`.** It runs inside the
  interceptor pipeline with `attempts: 3`, and an `INSERT` is not idempotent —
  a retry writes the row twice. Writes go through
  `getExecutionContext().client.statementExecution.executeStatement`, which has
  no retry. `warehouseId` on that context is a **`Promise<string> | undefined`**:
  `await` it and handle the empty case.
- **`server.extend` registers straight on Express, which does not forward
  rejected promises.** An async route needs its own `try/catch` or a warehouse
  failure becomes a hung request.
- **Every value goes in `parameters`** (`{name, type?, value?}`, value always a
  string, omitted = NULL), never concatenated. `registrado_em` comes from the
  warehouse's `current_timestamp()`, not the clicking browser's clock.

**The grant for writing is scoped to ONE table:**
`GRANT MODIFY ON TABLE …gold.retorno_ligacao`, never `ON SCHEMA` — `MODIFY` on
the schema would let the app rewrite `fato_vendas`.

**Reading identity in an AppKit app is decided by the FILENAME, not the call
site:** `x.sql` executes as the app's **service principal**; `x.obo.sql`
executes as the signed-in **user**. All four queries here are plain `.sql`, so
they depend entirely on the three `GRANT`s given to the service principal —
`USE CATALOG` on the catalog, `USE SCHEMA` + `SELECT` on `gold`. Declaring the
warehouse with `CAN_USE` grants **compute, not data**: without those grants the
app loads, does not error, and shows empty panels. Read the principal fresh
with `databricks apps get <app> -o json` (`service_principal_client_id`) — it
is new for every app created, never copy it between environments.

**Layer doctrine, enforced by the code:** raw is a file, bronze is a table, and
bronze is the data *as it arrived* — `cnpj` keeps its surrounding spaces
(`" 17810801326773 "`, length 16), `ativo` stays `S`/`N`, empty dates stay empty.
Cleaning happens in silver. Don't "fix" bronze.

**Silver cleans but never discards.** The invariant that proves it: revenue must
not move. `SUM(valor_total)` on bronze where `status <> 'Cancelado'` equals
`SUM(valor_liquido)` on `silver.pedidos` — **102,303,828.05** both sides. Returns
(2,327 items with negative quantity), cancellations (957), discontinued SKUs (76)
and orphaned portfolios (441 open portfolios whose salesperson left) all **stay**,
flagged in a column. Dropping the returns alone would inflate revenue by over a
million. Business problems get exposed, not silently corrected.

**102,303,828.05 is the number that must survive every layer**, and it carries
into gold: `SUM(receita)` on `gold.fato_vendas` and on the two sales marts all
equal it. That is what "conformed" means here, and test 1 enforces it. Two things
make it work and are easy to break:

- **Returns stay *inside* the fact**, with negative quantity and revenue plus a
  `devolucao` flag. Exclude them and gold sums 103,568,586.35 against silver's
  102,303,828.05 — a 1.26M gap between two layers of one pipeline. Gross revenue
  is `SUM(receita) FILTER (WHERE NOT devolucao)`.
- **Cancelled orders are filtered out** by the fact's contract
  (`WHERE NOT p.cancelado`), which is why the fact has 191,080 rows against
  197,724 silver items — the 6,644 difference is the items of those 957 orders.
  `COUNT(*) / COUNT(DISTINCT pedido_id)` ≈ **6.9**; if it reads ~13.8, a join
  duplicated rows.

The second bundle (`rotaperfume/`), an untouched `default-python` scaffold
pointing at a catalog that never existed, was **deleted** — it only confused
readers. There is no second workspace.

## Databricks conventions

Per `AGENTS.md` in each bundle (which its `CLAUDE.md` pulls in via `@AGENTS.md`):
**load the `databricks-core` skill before doing any Databricks work**, then the
matching product skill (`databricks-dabs`, `databricks-jobs`,
`databricks-unity-catalog`, …).

- **Always pass `--profile` explicitly**, matching the directory per the table
  above. Never rely on default profile resolution, even though `rotaperfume` is
  configured as the default.
- This is Databricks Free Edition: everything is serverless. Never configure a
  cluster.
- Scripts are PowerShell. Avoid naming a parameter `$Profile` — it shadows the
  PowerShell automatic variable; the scripts use `$DatabricksProfile`.

## Commands

Run from `rotaperfumes/`. The profile in this checkout is `rotaperfumes`; the
public `README.md` writes it as `meu-perfil` because a reader's will differ.

```powershell
uv sync --dev                                              # install deps
uv run pytest                                              # all tests (needs a live workspace via DB Connect)
uv run pytest tests/test_x.py::test_name                   # single test
uv run ruff check . ; uv run ruff format .                 # lint / format (line-length 120)

.\scripts\configurar.ps1                                   # ONCE: creates the gitignored variable files
.\scripts\criar-catalogo.ps1 rotaperfumes                  # catalog first — deploy needs it to exist
databricks bundle validate --strict --target dev --profile rotaperfumes
databricks bundle deploy --target dev --profile rotaperfumes
.\scripts\subir-raw.ps1 rotaperfumes                       # volume must exist before upload
databricks bundle run rotaperfume_pipeline --target dev --profile rotaperfumes
.\scripts\rodar-tarefa.ps1 rotaperfumes <task_key>         # ONE task, isolated — deps are assumed materialized
```

That order matters three times: the variables must exist before any bundle
command resolves, the catalog must exist before `deploy` creates the schemas,
and the Volume must exist before any file is uploaded into it.

`pytest` is not hermetic — `tests/conftest.py` eagerly opens a Databricks Connect
session at collection time and falls back to `DATABRICKS_SERVERLESS_COMPUTE_ID=auto`
if no compute is configured. There is no way to run the suite offline.

## Known pitfalls

- **Don't use `mode: development` on a target that declares UC schemas.** It
  prefixes every resource name with `[dev <user>]`, including schemas, which
  become `dev_fulano_bronze` and break every hard-coded SQL reference.
  `rotaperfumes/databricks.yml` uses `presets: { trigger_pause_status: PAUSED }`
  instead — that was the only effect of the mode worth keeping.
- **`workspace.host` does not accept a bundle variable.** It is auth config and is
  resolved before variables, so `${var.x}` there fails with `invalid character
  "{" in host name`. The host is therefore absent from both `databricks.yml`
  files and comes from `--profile`. Verified by trying it.
- **Creating the catalog cannot go in the bundle.** On Free Edition with Default
  Storage enabled, the UC API rejects `CREATE CATALOG` for lack of a MANAGED
  LOCATION (`Metastore storage root URL does not exist … 400 INVALID_STATE`).
  `scripts/criar-catalogo.ps1` does it via SQL; `CREATE CATALOG IF NOT EXISTS`
  works.
- **`databricks fs cp` needs the `dbfs:` scheme on the destination** even when
  the destination is a Unity Catalog Volume: `dbfs:/Volumes/<catalog>/bronze/raw/erp`.
- **`ruff` needs the notebook globals declared.** `spark`/`dbutils` are injected
  by the Databricks runtime; `pyproject.toml` lists them under
  `[tool.ruff] builtins` or `src/` fails F821.
- **`_metadata.file_path` comes back with a `dbfs:` prefix** even for a UC Volume
  — `dbfs:/Volumes/<catalog>/bronze/raw/erp/pedidos.csv`. Same scheme quirk as
  `databricks fs cp`.
- **Bronze ids are STRING, so compare with a `CAST`.** `WHERE vendedor_id > '40'`
  is a string comparison and matches `'5'`; use `CAST(vendedor_id AS INT) > 40`.
- **Serverless cold starts dominate the clock.** A warm run of the two-task job
  takes ~2min30; after the SQL Warehouse or serverless compute goes idle, the
  first query or run can take several minutes. Wake it before a live demo.
- **DBSQL runs in ANSI mode: use `try_to_date`, never `to_date`.** A malformed
  date *aborts the query* with `CAST_INVALID_INPUT` instead of returning NULL.
  Source dates come in two formats mixed in one column, so every conversion is
  `coalesce(try_to_date(x), try_to_date(x, 'dd/MM/yyyy'))`.
- **Never cast a CNPJ to a number** — 309 clients have a leading zero that a
  numeric type silently eats. It stays `STRING`, normalized with
  `lpad(regexp_replace(trim(cnpj),'[^0-9]',''), 14, '0')`.
- **`valor_liquido >= 0` is the wrong constraint on `silver.pedidos`** — 135
  orders are legitimately negative because they contain returned items. The
  correct rule is `NOT cancelado OR valor_liquido = 0`.
- **`raise_error()` returns type `NOTHING`**, so it cannot stand alone in a
  SELECT. It lives inside `CASE WHEN <good> THEN 'PASSOU' ELSE raise_error(…) END`.
  That is how `src/gold/08-testes.sql` stops the job.
- **`SELECT * REPLACE (…)` does not parse** on this SQL Warehouse
  (`PARSE_SYNTAX_ERROR`). Write the column list out.
- **When a test fails, fix the transformation — never the test.** The `testes`
  task is last and mandatory; when it goes red nothing downstream runs and the
  dashboard keeps yesterday's data, which beats today's wrong data.
- **Lakeview JSON has four rules that silently break widgets.** Dataset queries
  use **bare table names** (`FROM fato_vendas`) — a catalog prefix makes
  `dataset_catalog`/`dataset_schema` be ignored. `query.fields[].name` must match
  `encodings.*.fieldName` exactly. Widget versions are fixed: `counter`/`table`/
  filters = 2, `bar`/`line` = 3. Every page needs `"layoutVersion": "GRID_V1"`
  and each grid row must sum to `width` 12.
- **A dataset measure must not share its name with a column it aggregates.** A
  measure `Receita` defined as ``SUM(`receita`)`` resolves `receita` to itself and
  the dashboard fails at render time with
  `Circular reference detected in calculated field: receita`. Name them apart —
  `Receita Total` over `receita`. This does not surface at deploy: `bundle deploy`
  succeeds and the dashboard only breaks when someone opens it.
- **Keep the dashboard on one dataset.** Cross-filtering only works between
  widgets sharing a dataset, so a `LIMIT`-ed "top N" widget would opt itself out;
  sort descending instead.
- **Deleting a dashboard and redeploying gives it a NEW id and URL.** The content
  comes back identical, the link does not — re-read it from `bundle summary`.
- **`bundle` commands must run from inside `rotaperfumes/`**, or they fail with
  `Unable to locate the bundle root`.
- **Never build an ML feature from `gold.dim_cliente`.** Its `dias_sem_comprar`,
  `receita_acumulada` and `total_pedidos` are aggregated over the whole base with
  no cutoff — using any of them is leakage. Features come from `fato_vendas`,
  `silver.oportunidades` and `silver.visitas`, each filtered `< referencia` on the
  first line of the read. Negative `recencia_dias` is the signature of a source
  that escaped the filter.
- **`F.least()` ignores NULLs** — `least(NULL, 10)` returns `10`, not NULL. Capping
  `atraso_relativo` that way silently gave all 105 single-order clients the maximum
  alarm value and floated them to the top of the call queue. Use
  `when(razao > 10, 10).otherwise(razao)`, which propagates the NULL.
- **Escape single quotes in `COMMENT` strings.** A comment containing
  `'Fechado ganho'` ends the SQL literal and fails with `PARSE_SYNTAX_ERROR`;
  double them (`''`) when building the statement.
- **The dataset's "today" is 2026-08-31**, the max `data_pedido`. Never use
  `current_date()` in ML code — the day the notebook runs has nothing to do with
  the day the data knows.
- **`atraso_relativo` is non-monotonic, and that is the point of the ML night.**
  Purchase rate by band: <0.5 → 0.5% · 0.5–1.0 → 17.6% · **1.0–1.5 → 36.6%** ·
  1.5–3.0 → 14.4% · ≥3.0 → **0%**. The peak is in the middle, so sorting the
  column descending puts the 0% group first — AUC 0.78 yet only **1** hit in the
  top 200. No single-column sort can express this; a tree can. Both ends of
  `recencia_dias` also yield **zero** buyers in a top-200 list.
- **MLflow on serverless is 2.x**: `log_model(..., artifact_path="modelo")`, never
  MLflow 3's `name=`. `MlflowClient().get_registered_model(...).latest_versions`
  does **not** work against the Unity Catalog registry — register in a separate
  step and read `mlflow.register_model(...).version`. And call
  `WorkspaceClient().workspace.mkdirs(...)` before `set_experiment`, or you get
  `BAD_REQUEST: For input string: "None"`, which never mentions a folder.
- **Score with `predict_proba`, never `pyfunc.predict`** (returns the class and
  flattens the column to 0/1), and never `pyfunc.spark_udf` on serverless
  (`InvalidVersion: '18.x-aarch64-photon-scala2'`). Read column order from
  `modelo.feature_names_in_` — wrong order gives wrong numbers, not an error.
- **Salesperson names are NOT unique.** `silver.vendedores` has two
  `Henrique Oliveira` (ids 34, 36) and two `Vinícius Lopes` (31, 37). Key
  anything per-salesperson on `vendedor_id`; grouping by name silently merges two
  people's queues — `COUNT(DISTINCT vendedor)` reads 35 where `vendedor_id`
  reads 36.
- **Filter eligibility BEFORE `LIMIT`, not after.** Six of the 42 salespeople are
  terminated with live portfolios; filtering after `ORDER BY score DESC LIMIT 200`
  leaves **165** rows instead of 200.
- **`LIMIT` cannot take a function parameter** — `LIMIT p_quantos` fails with
  `INVALID_LIMIT_LIKE_EXPRESSION.IS_UNFOLDABLE`. Filter on a precomputed rank
  column instead.
- **Genie IS a DABs resource type — as of CLI v1.14.0.** `resources.genie_spaces`
  takes a `file_path` pointing at a `.geniespace.json`, plus `title`,
  `description`, `warehouse_id` and `parent_path`. `databricks bundle generate
  genie-space --existing-id … --key …` round-trips a UI-built space into the
  bundle. **The two spaces in this repo are managed differently, on purpose:**
  the *comercial* one predates this and is still CLI-created
  (`databricks genie create-space`, payload in `resources/genie-comercial.json`,
  not a bundle resource); the *direção* one is a bundle resource
  (`resources/genie-direcao.genie_space.yml` + `resources/direcao.geniespace.json`,
  key `genie_direcao`). Renaming a bundle resource key deletes and recreates the
  space with a **new id and URL**, and the app embeds that id — never rename it.
  `parent_path` is immutable and must exist before the first deploy
  (`databricks workspace mkdirs`).
- **The `serialized_space` schema has four rules that fail the deploy.**
  32-hex lowercase `id`s unique across *all three* lists combined; every text
  field is an **array of strings**; at most **one** `text_instructions` entry;
  and sort order matters — `data_sources.tables` by `identifier`, each
  `column_configs` by `column_name`, `example_question_sqls` and
  `text_instructions` by `id`. Ids here are **md5 of the content**, so a redeploy
  produces a byte-identical file instead of churning the diff. Run
  workspace/Genie path commands from **PowerShell** — Git Bash rewrites
  `/Users/...` into a Windows path.
- **Every column in `gold` must carry a `COMMENT`, and a task enforces it.**
  `src/gold/13-auditoria-metadado.sql` (task `auditoria_de_metadado`, the last in
  the DAG) raises on any gold table or column with an empty comment. Adding a
  column to a gold table without a comment turns the pipeline red. Column
  comments go in `ALTER TABLE … ALTER COLUMN … COMMENT` after the CTAS — a
  `CREATE OR REPLACE TABLE … AS SELECT` cannot carry them inline, and it **wipes
  them on every run**, which is why the ALTERs live in the same file. Silver
  (97 columns) and bronze (106) are deliberately out of scope: bronze is the data
  as it arrived, and silver is the next debt to pay.
- `tests/conftest.py` ships from the template with two unsorted-import (`I001`)
  findings. Pre-existing, autofixable, untouched so far.
- **The `'Todos'` sentinel needs the CAST on the COLUMN side.** `fila.sql`
  filters `WHERE :vendedor_id = 'Todos' OR CAST(f.vendedor_id AS STRING) =
  :vendedor_id`. Comparing the INT column directly against the STRING parameter
  makes DBSQL cast `'Todos'` to a number and **abort** with
  `CAST_INVALID_INPUT` — the `OR` does **not** short-circuit. Verified by
  running both forms. `npm run typegen` will never catch this: `DESCRIBE QUERY`
  parses the statement without executing it, so the query types cleanly and
  then explodes at runtime.
- **`vendeu` is a SUBSET of `trabalhados` — never chart them side by side.** The
  original Acompanhamento chart was a vertical `BarChart` with
  `yKey={['trabalhados','vendeu']}` over 36 sellers, and it failed three ways at
  once: 36 proper names on an x-axis are an unreadable blur; two sibling bars
  invite the eye to add a subset to its own superset; and sellers with nothing
  worked vanished, so the bar never showed how big that person's queue was. The
  fix is one **horizontal, stacked** bar per seller whose full length IS the
  queue — `Vendeu` + `Sem venda` + `A ligar` — capped at 12 sellers with the
  number dropped stated in the caption. Two mechanics to remember: ECharts draws
  the **first category at the bottom** in horizontal mode, so `.reverse()` after
  sorting or the best seller lands in the footer; and colors come from
  `useThemeColors('sequential')` (indices 7/4/1 = strongest outcome first), never
  hex — it is the only way the ramp survives the dark theme.
- **The warehouse sends every number as a STRING over JSON**, even where the
  generated type says `number` — the type describes the column, the transport
  delivers text. `"556423.71".toLocaleString('pt-BR')` returns the string
  unchanged and `"7" + "12"` is `"712"`. Everything goes through
  `client/src/lib/formato.ts:num()` before being formatted or summed.
- **`npm run typegen` degrades to `OFFLINE` on a cold warehouse** and writes
  `{}` types, which breaks `tsc` far from the cause. Start the warehouse first;
  if the first call still degrades, `npm run typegen -- --wait` blocks instead
  of degrading. The generator never overwrites good committed types with
  degraded ones.
- **`shared/appkit-types/` is generated and marked DO NOT EDIT** — it is in
  `eslint.config.js`'s ignore list, because linting a file the toolchain
  rewrites every build produces errors nobody can fix.
- **The scaffold's own `App.tsx` fails `appkit lint`**: it syncs the mobile nav
  with `useEffect` (`react-hooks/set-state-in-effect`). Render the `Sheet` only
  when `isMobile` — unmounting takes the state with it, so there is nothing to
  sync. Treat `apps init` output as starter code, not as requirements.
- **Two salespeople share a name inside `fila_semanal`** (36 by `vendedor_id`,
  35 by name). The app's vendor filter keys on `vendedor_id` and `vendedores.sql`
  appends the id to the label when a name repeats — otherwise the dropdown shows
  two visually identical options (`Henrique Oliveira`, ids 34 and 36, five
  contacts each).
- **`useAnalyticsQuery` has no `refetch`** — it returns
  `{data, loading, error, errorCode, warehouseStatus}` and nothing else. The only
  lever to re-run a query is remounting its caller, so `SemanaPage` keeps the
  filter, the typed comments and a `recarga` counter in the parent and remounts
  the child with `key={recarga}` after each write. **Do not fake a cache-busting
  SQL parameter** (`:recarga >= 0`): a browser still holding the previous JS
  sends the query without it and the warehouse rejects with
  `UNBOUND_SQL_PARAMETER` — the screen breaks itself after a deploy.
- **Query caching can only be turned off at the top of `createApp`.**
  `analytics({ cache: { enabled: false } })` **typechecks and is silently
  ignored** — `IAnalyticsConfig` has no `cache` key, and the plugin hardcodes
  `{ enabled: true, ttl: 3600 }` without ever reading its config. Without
  `createApp({ cache: { enabled: false } })` the app would serve hour-old rows
  after someone clicks.
- **`npm run dev` does not work in this template on Windows.** The script is
  `NODE_ENV=development tsx watch …` and npm runs it through `cmd.exe`:
  `'NODE_ENV' não é reconhecido`. Run the binary directly from Git Bash:
  `NODE_ENV=development npx tsx --tsconfig ./tsconfig.server.json
  --env-file-if-exists=./.env ./server/server.ts`. Local dev authenticates with
  the profile in `.env` and has **no OAuth headers**, so `registrado_por` falls
  back to the dev value — that is expected, not a bug.
- **The AppKit execution-context docs are stale.** They describe
  `getCurrentUserId()`, `getWarehouseId()` and `getWorkspaceId()`, none of which
  are exported. `getWorkspaceClient()` *is* exported but comes from the
  **Lakebase** connector, not the context — using it is a silent trap. Trust the
  `.d.ts`, not the prose. The `ExecutionContext` type itself is not exported.
- Prefer Volumes over DBFS: a Volume is a UC object with an owner, permissions,
  and lineage.
- The root `.gitignore` is the one that matters for identity: it excludes
  `**/.databricks/` and `**/variable-overrides.json` on top of the per-bundle
  ignores. Adding a new place where workspace values live means adding it there.
