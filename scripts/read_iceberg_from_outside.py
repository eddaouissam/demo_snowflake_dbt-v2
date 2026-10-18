"""
Read the dbt-built Iceberg tables from OUTSIDE Snowflake.

    Snowflake (dbt)  --writes-->  Iceberg tables (Snowflake storage)
                                        |
                     Horizon Iceberg REST catalog (/polaris/api/catalog)
                                        |
                     PyIceberg (catalog client)  +  DuckDB (query engine)

No Snowflake warehouse is used here : PyIceberg asks Horizon for the table
metadata, Horizon vends short-lived storage credentials, and the Parquet files
are read directly. Access is governed by ICEBERG_READER_ROLE's grants.

Auth : key-pair. We sign a standard Snowflake JWT with the service user's
private key ; PyIceberg exchanges it for an OAuth access token
(grant_type=client_credentials, client_secret=<JWT>, scope=session:role:<ROLE>).

Environment variables
---------------------
  SNOWFLAKE_ACCOUNT         ORGNAME-ACCOUNTNAME  (same value as the CI secret)
  ICEBERG_READER_USER       default: ICEBERG_READER
  ICEBERG_READER_ROLE       default: ICEBERG_READER_ROLE
  ICEBERG_READER_PRIVATE_KEY      PEM content of the private key (CI), or
  ICEBERG_READER_PRIVATE_KEY_PATH path to the .p8 file (local)
  ICEBERG_DATABASE          default: DBT_DEV_DB   (= Iceberg catalog "warehouse")
  ICEBERG_SCHEMA            default: DBT_SCHEMA   (= Iceberg namespace)

Run
---
  pip install "pyiceberg[pyarrow,duckdb]" pyjwt cryptography
  python scripts/read_iceberg_from_outside.py
"""

import base64
import hashlib
import os
import sys
import time

import jwt  # PyJWT
from cryptography.hazmat.primitives import serialization
from pyiceberg.catalog import load_catalog

# --------------------------------------------------------------------------
# Config
# --------------------------------------------------------------------------
ACCOUNT = os.environ["SNOWFLAKE_ACCOUNT"].strip()
USER = os.getenv("ICEBERG_READER_USER", "ICEBERG_READER").upper()
ROLE = os.getenv("ICEBERG_READER_ROLE", "ICEBERG_READER_ROLE").upper()
DATABASE = os.getenv("ICEBERG_DATABASE", "DBT_DEV_DB").upper()
SCHEMA = os.getenv("ICEBERG_SCHEMA", "DBT_SCHEMA").upper()

HORIZON_URI = f"https://{ACCOUNT.lower()}.snowflakecomputing.com/polaris/api/catalog"

# Tables built by dbt as Iceberg (see dbt_project.yml / rpt_revenue_by_region.sql)
ICEBERG_TABLES = ["DIM_CUSTOMERS", "FCT_ORDERS", "FCT_DAILY_REVENUE", "RPT_REVENUE_BY_REGION"]


def load_private_key():
    pem = os.getenv("ICEBERG_READER_PRIVATE_KEY")
    if not pem:
        path = os.getenv("ICEBERG_READER_PRIVATE_KEY_PATH")
        if not path:
            sys.exit("Set ICEBERG_READER_PRIVATE_KEY or ICEBERG_READER_PRIVATE_KEY_PATH")
        with open(path, "rb") as f:
            pem = f.read().decode()
    return serialization.load_pem_private_key(pem.encode(), password=None)


def snowflake_jwt(private_key) -> str:
    """Standard Snowflake key-pair JWT (same format the Python connector builds)."""
    # JWT account = account identifier, uppercase, without any region / cloud suffix
    jwt_account = ACCOUNT.split(".")[0].upper()
    qualified_user = f"{jwt_account}.{USER}"

    public_der = private_key.public_key().public_bytes(
        serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo
    )
    fingerprint = "SHA256:" + base64.b64encode(hashlib.sha256(public_der).digest()).decode()

    now = int(time.time())
    payload = {
        "iss": f"{qualified_user}.{fingerprint}",
        "sub": qualified_user,
        "iat": now,
        "exp": now + 3540,  # < 1h, Snowflake's max
    }
    return jwt.encode(payload, private_key, algorithm="RS256")


def main() -> None:
    token = snowflake_jwt(load_private_key())

    # One Snowflake database = one Iceberg catalog ("warehouse") ; schema = namespace
    catalog = load_catalog(
        "horizon",
        **{
            "type": "rest",
            "uri": HORIZON_URI,
            "warehouse": DATABASE,
            "credential": token,  # no ':' -> sent as client_secret
            "scope": f"session:role:{ROLE}",
            "oauth2-server-uri": f"{HORIZON_URI}/v1/oauth/tokens",
            # Horizon vends short-lived storage creds -> read Parquet directly
            "header.X-Iceberg-Access-Delegation": "vended-credentials",
        },
    )

    print(f"Connected to Horizon catalog {DATABASE} as role {ROLE}\n")
    visible = {ident[-1].upper() for ident in catalog.list_tables(SCHEMA)}
    print(f"Iceberg tables visible in {SCHEMA} : {sorted(visible)}\n")

    missing = [t for t in ICEBERG_TABLES if t not in visible]
    if missing:
        sys.exit(f"FAIL : not visible through Horizon : {missing} (Iceberg ? grants ?)")

    # ---- Iceberg metadata : what dbt actually produced ----------------------
    daily = catalog.load_table(f"{SCHEMA}.FCT_DAILY_REVENUE")
    print(f"FCT_DAILY_REVENUE  (format v{daily.format_version})")
    print(f"  location : {daily.location()}")
    print(f"  schema   : {[f.name for f in daily.schema().fields]}")
    print("  snapshots (each dbt run = new snapshot) :")
    for snap in daily.snapshots()[-5:]:
        op = snap.summary.operation.value if snap.summary else "?"
        ts = time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime(snap.timestamp_ms / 1000))
        print(f"    {snap.snapshot_id}  {ts} UTC  {op}")
    print()

    # ---- Query with DuckDB : zero Snowflake compute -------------------------
    rpt = catalog.load_table(f"{SCHEMA}.RPT_REVENUE_BY_REGION")
    con = rpt.scan().to_duckdb(table_name="rpt_revenue_by_region")
    orders = catalog.load_table(f"{SCHEMA}.FCT_ORDERS")
    orders.scan().to_duckdb(table_name="fct_orders", connection=con)

    print("DuckDB -> governed metrics (computed by the semantic view, stored as Iceberg) :")
    print(
        con.sql(
            """
            SELECT region,
                   SUM(total_revenue) AS total_revenue,
                   SUM(order_count)   AS order_count
            FROM rpt_revenue_by_region
            GROUP BY region
            ORDER BY total_revenue DESC
            """
        )
    )

    # Cross-check : same revenue recomputed from the raw fact, outside Snowflake
    check = con.sql(
        """
        SELECT
            (SELECT SUM(total_revenue)     FROM rpt_revenue_by_region) AS from_semantic_view,
            (SELECT SUM(recognized_amount) FROM fct_orders)            AS from_fact
        """
    ).fetchone()
    print(f"Revenue from semantic view : {check[0]}  |  recomputed from fct_orders : {check[1]}")
    if check[0] is None or check[0] != check[1]:
        sys.exit("FAIL : external read does not match")
    print("\nOK : Snowflake-managed Iceberg tables read from outside Snowflake.")


if __name__ == "__main__":
    main()
