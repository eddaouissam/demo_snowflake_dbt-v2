# demo_snowflake_dbt-v2

### **Author:** Issam Ed-Daou ·  [Portfolio](https://eddaouissam.github.io/)


CI/CD pipeline for dbt using Snowflake's **native dbt integration** — no local dbt install needed — with a governed **semantic layer** built on Snowflake **Semantic Views**, and marts stored as open **Apache Iceberg™ tables** on Snowflake storage (readable from outside Snowflake).

This is the V2 of [demo_snowflake_dbt](https://github.com/eddaouissam/demo_snowflake_dbt). The main difference is that dbt now runs entirely inside Snowflake (Workspaces + dbt Project objects), and orchestration is handled by Snowflake Tasks instead of GitHub Actions cron. On top of the pipeline, the project materializes a native Snowflake Semantic View from dbt using the [`dbt_semantic_view`](https://hub.getdbt.com/Snowflake-Labs/dbt_semantic_view/latest/) package.

## How it works

```
┌─────────────────────────────────────────────────────────────────────┐
│                        SNOWFLAKE WORKSPACE                         │
│                     (develop dbt models here)                      │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ git push (feature branch)
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                            GITHUB                                  │
│                                                                    │
│   feature/branch ──── Pull Request ────── merge to main            │
│                             │                      │               │
│                             ▼                      ▼               │
│                     ┌──────────────┐      ┌──────────────┐         │
│                     │  CI Workflow  │      │  CD Workflow  │         │
│                     │              │      │              │         │
│                     │  deploy test │      │  deploy prod │         │
│                     │  dbt run     │      │  setup tasks │         │
│                     │  dbt test    │      │              │         │
│                     └──────┬───────┘      └──────┬───────┘         │
│                            │                     │                 │
└────────────────────────────┼─────────────────────┼─────────────────┘
                             │                     │
                             ▼                     ▼
┌─────────────────────────────────────────────────────────────────────┐
│                          SNOWFLAKE                                 │
│                                                                    │
│   ┌──────────────┐                    ┌──────────────┐             │
│   │  DBT_DEV_DB  │                    │  DBT_PROD_DB │             │
│   │              │                    │              │             │
│   │  tester dbt  │                    │  prod dbt    │             │
│   │  project obj │                    │  project obj │             │
│   └──────────────┘                    └──────┬───────┘             │
│                                              │                     │
│                                    ┌─────────┴─────────┐           │
│                                    │  SNOWFLAKE TASKS   │           │
│                                    │                    │           │
│                                    │  daily_run (cron)  │           │
│                                    │       │            │           │
│                                    │       ▼            │           │
│                                    │  daily_test        │           │
│                                    └────────────────────┘           │
└─────────────────────────────────────────────────────────────────────┘
```

## Repo structure

```
├── .github/workflows/
│   ├── incoming_pr.yml            # CI — test on PRs
│   └── pr_merged.yml              # CD — deploy on merge
├── config_scripts/
│   ├── Setup Snow.sql             # Snowflake env setup (roles, DBs, grants, ext. access)
│   └── schedules.sql              # Snowflake Tasks definitions
├── demosnowdbt/
│   ├── models/
│   │   ├── staging/               # views — light cleaning of raw data
│   │   │   ├── stg_customers.sql
│   │   │   ├── stg_orders.sql
│   │   │   └── stg_example.sql    # CI/CD smoke-test model
│   │   ├── marts/                 # ICEBERG tables — business-ready facts & dims
│   │   │   ├── dim_customers.sql
│   │   │   ├── fct_orders.sql
│   │   │   └── fct_daily_revenue.sql      # incremental (MERGE) on Iceberg
│   │   └── semantics/             # the semantic layer
│   │       ├── sem_orders.sql             # native SEMANTIC VIEW (dbt-materialized)
│   │       └── rpt_revenue_by_region.sql  # ICEBERG table built FROM the semantic view
│   ├── macros/
│   │   └── iceberg_snowflake_managed.sql  # workaround : base_location vs SNOWFLAKE_MANAGED
│   ├── tests/
│   │   └── assert_models_are_iceberg.sql  # fails if a model isn't physically Iceberg
│   ├── seeds/
│   │   ├── raw_customers.csv      # self-contained demo data
│   │   └── raw_orders.csv
│   ├── dbt_project.yml
│   ├── packages.yml               # Snowflake-Labs/dbt_semantic_view
│   └── profiles.yml
├── scripts/
│   └── read_iceberg_from_outside.py  # PyIceberg + DuckDB via Horizon REST catalog
└── README.md
```

## Setup

### 1. Snowflake

Run `config_scripts/Setup Snow.sql` as `ACCOUNTADMIN`. It creates the role, warehouse, databases, schemas and grants — plus two things needed for the semantic layer :

- `GRANT CREATE SEMANTIC VIEW` on the dbt schemas (semantic views are a distinct object type)
- the `DBT_HUB_INTEGRATION` external access integration, so `dbt deps` running **inside Snowflake** can pull the `dbt_semantic_view` package from the dbt hub
- `GRANT CREATE ICEBERG TABLE` on the dbt schemas (Iceberg tables are a distinct object type)
- a read-only `ICEBERG_READER_ROLE` + `ICEBERG_READER` service user (key-pair) for the external engine demo — paste your public key in the script first

Then grant task execution privileges :

```sql
USE ROLE ACCOUNTADMIN;
GRANT EXECUTE TASK ON ACCOUNT TO ROLE DBT_ROLE;
GRANT EXECUTE MANAGED TASK ON ACCOUNT TO ROLE DBT_ROLE;
```

### 2. GitHub

Create an environment named `prod` in your repo settings (Settings → Environments).

**Secrets :**

| Name | Value |
|---|---|
| `SNOWFLAKE_ACCOUNT` | your account identifier |
| `SNOWFLAKE_USER` | your username |
| `SNOWFLAKE_PASSWORD` | your password |
| `ICEBERG_READER_PRIVATE_KEY` | *(optional)* content of `iceberg_reader_key.p8` — enables the external-read CI step |

**Variables :**

| Name | Value |
|---|---|
| `SNOWFLAKE_DATABASE` | `DBT_DEV_DB` |
| `SNOWFLAKE_SCHEMA` | `DBT_SCHEMA` |
| `SNOWFLAKE_ROLE` | `DBT_ROLE` |
| `SNOWFLAKE_WAREHOUSE` | `DBT_WH` |

### 3. Test it

```bash
git checkout -b feature/test-pipeline
# make a change in demosnowdbt/models/
git add . && git commit -m "test ci/cd" && git push origin feature/test-pipeline
```

Open a PR → CI runs → merge → CD deploys to prod. That's it.

## Workflows

**`incoming_pr.yml`** (CI) — triggers on PRs to `main`
- Deploys a tester dbt project object on `DBT_DEV_DB` (with the external access integration attached, so `dbt deps` resolves `dbt_semantic_view` on Snowflake)
- Runs `dbt seed` + `dbt run` + `dbt test` against dev
- Reads the freshly built Iceberg tables **from outside Snowflake** (PyIceberg + DuckDB) — only if `ICEBERG_READER_PRIVATE_KEY` is set

**`pr_merged.yml`** (CD) — triggers on merge to `main`
- Deploys the production dbt project object on `DBT_PROD_DB` (external access integration attached)
- Loads seed data with `dbt seed`
- Deploys Snowflake Tasks for daily orchestration

## The semantic layer

The dbt DAG flows raw → staging → marts → **semantic view** → consumption :

```
seeds (raw_*)  ──►  staging (stg_*)  ──►  marts (dim_/fct_)  ──►  sem_orders  ──►  rpt_revenue_by_region
   csv                 views                  tables             SEMANTIC VIEW        table (queries the SV)
```

**`sem_orders`** is a dbt model with `{{ config(materialized='semantic_view') }}`. Its body isn't a SELECT — it's Snowflake's `CREATE SEMANTIC VIEW` syntax, with `{{ ref() }}` inside the `TABLES` clause so dbt tracks lineage :

- **TABLES** — `fct_orders` and `dim_customers`, with primary keys and synonyms
- **RELATIONSHIPS** — the orders → customers join, declared once
- **FACTS** — row-level amounts
- **DIMENSIONS** — date, status, region, segment... with synonyms & comments (this metadata is what makes Cortex Analyst / AI agents effective)
- **METRICS** — `total_revenue`, `order_count`, `average_order_value`... defined once, consistent everywhere

**`rpt_revenue_by_region`** then consumes it like any downstream model :

```sql
SELECT * FROM SEMANTIC_VIEW(
  {{ ref('sem_orders') }}
  METRICS orders.total_revenue, orders.order_count
  DIMENSIONS customers.region, customers.segment
)
```

No aggregation logic duplicated — Snowflake computes the metrics from the governed definitions. Its dbt tests double as integration tests of the semantic layer.

Ad-hoc queries work the same way in Snowsight :

```sql
SELECT * FROM SEMANTIC_VIEW(
  DBT_PROD_DB.DBT_SCHEMA.SEM_ORDERS
  METRICS orders.total_revenue
  DIMENSIONS customers.region
);
```

**Why bother ?** One definition of "revenue" shared by SQL, BI tools and AI agents (Cortex Analyst reads semantic views natively), versioned in Git and deployed through the same CI/CD pipeline as the rest of the project.

> Note : the `dbt_semantic_view` package doesn't support `persist_docs` for semantic views — use the `COMMENT` clauses inside the model instead (as done in `sem_orders.sql`).

## Apache Iceberg tables

Every mart (and the `rpt_revenue_by_region` consumer) is an **Iceberg table stored by Snowflake itself** : Parquet data files + Iceberg metadata, but no S3 bucket, no IAM role, no external volume to set up. It's two lines of config in `dbt_project.yml` :

```yaml
flags:
  enable_iceberg_materializations: true   # required since dbt 1.9

models:
  demosnowdbt:
    marts:
      +materialized: table
      +table_format: iceberg
      +external_volume: SNOWFLAKE_MANAGED
```

dbt then generates `CREATE OR REPLACE ICEBERG TABLE ... EXTERNAL_VOLUME = 'SNOWFLAKE_MANAGED' CATALOG = 'SNOWFLAKE' AS (...)`. Everything downstream is unchanged : the semantic view `sem_orders` sits on top of Iceberg tables, `fct_daily_revenue` runs incremental `MERGE`s on Iceberg, tests run as usual.

> Snowflake storage for Iceberg is GA since June 2026, on **AWS and Azure** commercial regions. On GCP, point `external_volume` to your own volume (see `Setup Snow.sql`, step 6d).

### ⚠️ The `base_location` gotcha

dbt Core's Snowflake adapter (1.9 → 1.12) always adds `base_location = '_dbt/<schema>/<model>'` to the DDL, and Snowflake-managed storage rejects it :

```
BASE_LOCATION property is not supported for Iceberg tables using Snowflake Managed Storage.
```

([dbt-adapters#1911](https://github.com/dbt-labs/dbt-adapters/issues/1911) — dbt Fusion 2.0 already handles it.) `macros/iceberg_snowflake_managed.sql` overrides `snowflake__create_table_built_in_sql` : it **wraps** the adapter macro (`dbt.snowflake__create_table_built_in_sql`) and strips `base_location` only when the volume is `SNOWFLAKE_MANAGED`. No copy-paste of adapter code, so it survives dbt upgrades — delete it once the fix ships.

### Is it really Iceberg ?

`tests/assert_models_are_iceberg.sql` checks `INFORMATION_SCHEMA.TABLES.IS_ICEBERG` for every Iceberg model — `dbt test` fails if one silently falls back to a native table.

### Reading it from outside Snowflake

The point of Iceberg : other engines read the same tables. Snowflake exposes them through the **Horizon Iceberg REST catalog** :

```
https://<ORGNAME-ACCOUNTNAME>.snowflakecomputing.com/polaris/api/catalog
   catalog ("warehouse") = database     namespace = schema
```

`scripts/read_iceberg_from_outside.py` signs a key-pair JWT as `ICEBERG_READER`, lets PyIceberg exchange it for an OAuth token (scope `session:role:ICEBERG_READER_ROLE`), lists the snapshots dbt created, then queries the tables with **DuckDB** — no Snowflake warehouse involved — and checks the revenue matches the semantic view's.

```bash
pip install "pyiceberg[pyarrow,duckdb]" pyjwt cryptography
export SNOWFLAKE_ACCOUNT=ORGNAME-ACCOUNTNAME
export ICEBERG_READER_PRIVATE_KEY_PATH=./iceberg_reader_key.p8
python scripts/read_iceberg_from_outside.py
```

Access stays governed by Snowflake : the external engine only sees what `ICEBERG_READER_ROLE` is granted (future grants re-apply after each dbt `CREATE OR REPLACE`). Reads through Snowflake's engine cost nothing extra on Snowflake storage ; external engine requests are billed.

## Orchestration

Two chained Snowflake Tasks defined in `config_scripts/schedules.sql` :

- **`dbt_daily_run`** — runs `dbt run --target prod` every day at midnight UTC
- **`dbt_daily_test`** — runs `dbt test --target prod` right after

## V1 vs V2

| | V1 | V2 |
|---|---|---|
| Dev environment | Local (VS Code + dbt Core) | Snowflake Workspaces |
| Deployment | dbt CLI via GitHub Actions | Snowflake CLI (`snow dbt`) |
| Orchestration | GitHub Actions cron | Snowflake Tasks |
| Local install | Python + dbt Core | Nothing |

## Links

- [V1 repo](https://github.com/eddaouissam/demo_snowflake_dbt)
- [dbt_semantic_view package](https://github.com/Snowflake-Labs/dbt_semantic_view)
- [Snowflake docs — Semantic views](https://docs.snowflake.com/en/user-guide/views-semantic/overview)
- [Snowflake docs — CREATE SEMANTIC VIEW](https://docs.snowflake.com/en/sql-reference/sql/create-semantic-view)
- [Snowflake docs — Semantic views best practices](https://docs.snowflake.com/en/user-guide/views-semantic/best-practices-dev)
- [Snowflake docs — Snowflake storage for Iceberg tables](https://docs.snowflake.com/en/user-guide/tables-iceberg-internal-storage)
- [Snowflake docs — Query Iceberg tables with an external engine (Horizon)](https://docs.snowflake.com/en/user-guide/tables-iceberg-query-using-external-query-engine-snowflake-horizon)
- [dbt docs — Snowflake and Apache Iceberg](https://docs.getdbt.com/docs/build/iceberg/adapters/snowflake-iceberg-support)
- [Snowflake docs — dbt Projects](https://docs.snowflake.com/en/user-guide/data-engineering/dbt-projects-on-snowflake)
- [Snowflake docs — Schedule dbt runs](https://docs.snowflake.com/en/user-guide/data-engineering/dbt-projects-on-snowflake-schedule-project-execution)
- [LinkedIn](https://www.linkedin.com/in/m%E2%80%99hamed-issam-ed-daou-045674211/)

⭐ if this helped !
