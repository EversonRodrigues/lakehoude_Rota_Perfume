# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A teaching project that builds a Databricks lakehouse for a fictional perfume
distributor ("Rota Perfume") out of 10 flat CSVs. Three parts:

- `dados/` — the raw source data, split by source system: `erp/` (produtos,
  pedidos, itens_pedido, pagamentos, estoque) and `crm/` (clientes, vendedores,
  carteira, oportunidades, visitas). ~15 MB, 313,551 data rows;
  `itens_pedido.csv` is the big one (197,724 rows), `vendedores.csv` the small
  one (42). These files are the local stand-in for the ERP/CRM exports — they
  get uploaded to a Unity Catalog Volume, not read from disk by jobs.
- `rotaperfume/` and `rotaperfumes/` — **two near-identical Declarative
  Automation Bundles (DABs), one per workspace.** See below. All
  bundle/`uv`/`pytest` commands must be run from inside one of these
  directories, never the repo root.
- `.llm/prompt_01.md` — the course script for the first of six planned
  deliverables. Read it before extending a bundle; it carries the intended target
  architecture and pitfalls learned the hard way (see "Known pitfalls"). Written
  in Portuguese, as is the domain vocabulary throughout the data.

## The two bundles — pick the right one

`rotaperfumes/` is a copy of `rotaperfume/` pointed at a second Free Edition
workspace. The only differences are the bundle name/uuid, the package name in
`pyproject.toml`, the workspace host, and the catalog. **Directory, CLI profile,
and catalog must always agree:**

| Directory | `--profile` | Host | Catalog |
|---|---|---|---|
| `rotaperfume/` | `rotaperfume` | `dbc-3a577ebb-7807` | `lakehoude_Rota_Perfume` |
| `rotaperfumes/` | `rotaperfumes` | `dbc-73ba6d88-0c16` | `lakehouse_rotaperfume` |

`lakehoude_Rota_Perfume` is misspelled on purpose — it is the real catalog name
in that workspace. `rotaperfumes/` is the one whose catalog matches the naming
in `.llm/prompt_01.md`; the course script itself targets a third workspace
(`dbc-84cd5511-fa25`, profile `projeto-dados-ia`) that this checkout does not
have — treat its host/profile/warehouse-id as illustrative, not as values to copy.

When the user doesn't say which one, ask. Any change made to one bundle almost
always has to be mirrored into the other.

## Current state vs. intended state

Both bundles are **freshly scaffolded from the `default-python` template and
mostly empty**. `README.md` describes `src/` and `resources/`, and
`databricks.yml` has `include: resources/*.yml`, but neither directory exists
yet. `pyproject.toml` declares an entrypoint `main = "<pkg>.main:main"` with no
module behind it. Only `tests/conftest.py` (Databricks Connect + Spark fixtures,
serverless fallback) is real. The repo has **no commits yet** — the working tree
is the entire history so far.

The intended shape, per `.llm/prompt_01.md`:

- schemas `bronze`, `silver`, `gold` plus a MANAGED volume `bronze.raw`, all
  declared as bundle resources with `COMMENT`s
- CSVs land in `/Volumes/{catalog}/bronze/raw/erp` and `/crm` — **raw is a file
  in a Volume, bronze is a table**; the Volume keeps the ERP export byte-for-byte
- a single job `rotaperfume_pipeline` that gains one task per deliverable,
  starting with `raw_conferencia`: an arrival check that asserts all 10 files
  exist and are non-empty, records `(sistema, arquivo, bytes, linhas,
  conferido_em)` into a control table `bronze._raw_arquivos`, and **fails the
  job** if anything is missing. A missing file doesn't raise an error on its own
  — it just produces a smaller number that looks correct.

## Databricks conventions

Per `rotaperfume/AGENTS.md` (which `rotaperfume/CLAUDE.md` imports via
`@AGENTS.md`): **load the `databricks-core` skill before doing any Databricks
work**, then the matching product skill (`databricks-dabs`, `databricks-jobs`,
`databricks-unity-catalog`, …).

- **Always pass `--profile` explicitly**, matching the directory per the table
  above. Never rely on default profile resolution, even though `rotaperfume` is
  configured as the default.
- This is Databricks Free Edition: everything is serverless. Never configure a
  cluster.

## Commands

Run from `rotaperfume/` (or `rotaperfumes/`, swapping the profile):

```bash
uv sync --dev                                              # install deps
uv run pytest                                              # all tests (needs a live workspace via DB Connect)
uv run pytest tests/test_x.py::test_name                   # single test
uv run ruff check . && uv run ruff format .                # lint / format (line-length 120)

databricks bundle validate --target dev --profile rotaperfume
databricks bundle deploy   --target dev --profile rotaperfume
databricks bundle run rotaperfume_pipeline --target dev --profile rotaperfume
```

Order matters when bootstrapping: the catalog must exist before `deploy` creates
the schemas, and the Volume must exist before any file is uploaded into it.

`pytest` is not hermetic — `tests/conftest.py` eagerly opens a Databricks Connect
session at collection time and falls back to `DATABRICKS_SERVERLESS_COMPUTE_ID=auto`
if no compute is configured. There is no way to run the suite offline.

## Known pitfalls

- **Don't use `mode: development` on the dev target if UC schemas are bundle
  resources.** It prefixes every resource name with `[dev <user>]`, including
  schemas, which become `dev_fulano_bronze` and break every hard-coded SQL
  reference. Pause schedules with `presets: { trigger_pause_status: PAUSED }`
  instead. Both `databricks.yml` files currently *do* set `mode: development` —
  that is fine only while there are no schema resources, and must be revisited
  the moment `resources/catalogo.yml` is added.
- **Creating the catalog cannot go in the bundle.** On Free Edition with Default
  Storage enabled, the UC API rejects `CREATE CATALOG` for lack of a MANAGED
  LOCATION (`Metastore storage root URL does not exist … 400 INVALID_STATE`).
  Create it via SQL from a script instead; `CREATE CATALOG IF NOT EXISTS` works.
- **`databricks fs cp` needs the `dbfs:` scheme on the destination** even when
  the destination is a Unity Catalog Volume: `dbfs:/Volumes/<catalog>/bronze/raw/erp`.
- Prefer Volumes over DBFS: a Volume is a UC object with an owner, permissions,
  and lineage.
- The `prod` target in both `databricks.yml` files still carries the template
  author's identity (`everson101288@gmail.com`) in `root_path` and `permissions`.
  Fix that before any prod deploy.
- There is no `.gitignore` at the repo root — only inside each bundle. Editor and
  CLI scratch (`.vscode-cache/`, `.databricks/`) sits untracked at the root; don't
  commit it.
