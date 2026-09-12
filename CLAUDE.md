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
- `rotaperfume/` and `rotaperfumes/` — **two near-identical Declarative
  Automation Bundles (DABs), one per workspace.** See below. All
  bundle/`uv`/`pytest` commands must be run from inside one of these
  directories, never the repo root.
- `.llm/prompt_01.md` — the course script for deliverable 1. Read it before
  extending a bundle; it carries the target architecture and pitfalls learned the
  hard way. Written in Portuguese, as is the domain vocabulary throughout the
  data and the code.

## The two bundles — pick the right one

`rotaperfumes/` began as a copy of `rotaperfume/` pointed at a second Free
Edition workspace. **Directory, CLI profile, and catalog must always agree:**

| Directory | `--profile` | Host | Catalog | State |
|---|---|---|---|---|
| `rotaperfumes/` | `rotaperfumes` | `dbc-73ba6d88-0c16` | `lakehouse_rotaperfume` | deliverable 1 built and deployed |
| `rotaperfume/` | `rotaperfume` | `dbc-3a577ebb-7807` | see warning below | empty scaffold; catalog populated by hand |

Both profiles authenticate as `everson101288@gmail.com`, so the
`everson101288@gmail.com` in each `prod` block is correct, not a template
leftover.

**`rotaperfume/databricks.yml` has a real bug:** it sets
`catalog: lakehoude_Rota_Perfume`, a catalog that does not exist — the
misspelling is the repo folder name leaking into the YAML. The catalog actually
in that workspace is `lakehouse_rotaperfume`, correctly spelled, already
populated by hand: `bronze`/`silver`/`gold` with no COMMENTs, a volume
`bronze.tabelas_rotaperfume`, and all 10 bronze tables loaded manually. Porting
deliverable 1 there needs the name fixed *and* the pre-existing schemas resolved
(a DAB fails to create a schema that already exists — drop them or import them
into bundle state first).

The course script itself targets a third workspace (`dbc-84cd5511-fa25`, profile
`projeto-dados-ia`, warehouse `666be37e3fededf2`) that this checkout does not
have — treat those values as illustrative, never copy them.

## Current state — deliverables 1 and 2 are done in `rotaperfumes/`

Built and verified end-to-end against the `rotaperfumes` workspace. Each
deliverable has a course script in `.llm/prompt_0N.md` — `prompt_01.md` came with
the repo, `prompt_02.md` was written here from the measured run.

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
  silver**, never bronze. 10 tasks total in the job.
- `resources/dashboard-comercial.lvdash.json` + `resources/dashboard.dashboard.yml`
  (resource `dashboards.comercial`) — the AI/BI dashboard **as code**, deployed by
  the bundle, not clicked. 14 widgets over a **single** dataset `ds_vendas`, with
  the KPIs declared once as dataset `columns` and referenced via
  ``MEASURE(`Receita`)``.

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

`rotaperfume/` is still the untouched `default-python` scaffold: no `resources/`,
no `src/`, and a `main = "rotaperfume.main:main"` entrypoint with no module
behind it.

The repo has **no commits yet** — the working tree is the entire history so far.

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

Run from `rotaperfumes/` (or `rotaperfume/`, swapping the profile):

```powershell
uv sync --dev                                              # install deps
uv run pytest                                              # all tests (needs a live workspace via DB Connect)
uv run pytest tests/test_x.py::test_name                   # single test
uv run ruff check . ; uv run ruff format .                 # lint / format (line-length 120)

.\scripts\criar-catalogo.ps1 rotaperfumes                  # catalog first — deploy needs it to exist
databricks bundle validate --strict --target dev --profile rotaperfumes
databricks bundle deploy --target dev --profile rotaperfumes
.\scripts\subir-raw.ps1 rotaperfumes                       # volume must exist before upload
databricks bundle run rotaperfume_pipeline --target dev --profile rotaperfumes
```

That order matters twice: the catalog must exist before `deploy` creates the
schemas, and the Volume must exist before any file is uploaded into it.

`pytest` is not hermetic — `tests/conftest.py` eagerly opens a Databricks Connect
session at collection time and falls back to `DATABRICKS_SERVERLESS_COMPUTE_ID=auto`
if no compute is configured. There is no way to run the suite offline.

## Known pitfalls

- **Don't use `mode: development` on a target that declares UC schemas.** It
  prefixes every resource name with `[dev <user>]`, including schemas, which
  become `dev_fulano_bronze` and break every hard-coded SQL reference.
  `rotaperfumes/databricks.yml` uses `presets: { trigger_pause_status: PAUSED }`
  instead — that was the only effect of the mode worth keeping. `rotaperfume/`
  still sets `mode: development`; fix that before adding schema resources there.
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
- `tests/conftest.py` ships from the template with two unsorted-import (`I001`)
  findings. Pre-existing, autofixable, untouched so far.
- Prefer Volumes over DBFS: a Volume is a UC object with an owner, permissions,
  and lineage.
- There is no `.gitignore` at the repo root — only inside each bundle. Editor and
  CLI scratch (`.vscode-cache/`, `.databricks/`) sits untracked at the root.
