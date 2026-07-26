# demo_snowflake_dbt-v2

### **Author:** Issam Ed-Daou ·  [Portfolio](https://eddaouissam.github.io/)


CI/CD pipeline for dbt using Snowflake's **native dbt integration** — no local dbt install needed — now with a governed **semantic layer** built on Snowflake **Semantic Views**.

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
│   │   ├── marts/                 # tables — business-ready facts & dims
│   │   │   ├── dim_customers.sql
│   │   │   └── fct_orders.sql
│   │   └── semantics/             # the semantic layer
│   │       ├── sem_orders.sql             # native SEMANTIC VIEW (dbt-materialized)
│   │       └── rpt_revenue_by_region.sql  # table built FROM the semantic view
│   ├── seeds/
│   │   ├── raw_customers.csv      # self-contained demo data
│   │   └── raw_orders.csv
│   ├── dbt_project.yml
│   ├── packages.yml               # Snowflake-Labs/dbt_semantic_view
│   └── profiles.yml
└── README.md
```

## Setup

### 1. Snowflake

Run `config_scripts/Setup Snow.sql` as `ACCOUNTADMIN`. It creates the role, warehouse, databases, schemas and grants — plus two things needed for the semantic layer :

- `GRANT CREATE SEMANTIC VIEW` on the dbt schemas (semantic views are a distinct object type)
- the `DBT_HUB_INTEGRATION` external access integration, so `dbt deps` running **inside Snowflake** can pull the `dbt_semantic_view` package from the dbt hub

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
- [Snowflake docs — dbt Projects](https://docs.snowflake.com/en/user-guide/data-engineering/dbt-projects-on-snowflake)
- [Snowflake docs — Schedule dbt runs](https://docs.snowflake.com/en/user-guide/data-engineering/dbt-projects-on-snowflake-schedule-project-execution)
- [LinkedIn](https://www.linkedin.com/in/m%E2%80%99hamed-issam-ed-daou-045674211/)

⭐ if this helped !
