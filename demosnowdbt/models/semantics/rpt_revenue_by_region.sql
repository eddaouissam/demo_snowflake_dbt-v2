{{ config(
    materialized='table',
    table_format='iceberg',
    external_volume='SNOWFLAKE_MANAGED'
) }}

-- Downstream consumption : a regular dbt model that queries the semantic
-- view with SEMANTIC_VIEW(...). The metrics are computed by Snowflake from
-- the governed definitions — no aggregation logic is duplicated here.
--
-- Stored as an Iceberg table : the governed metrics end up in an OPEN format,
-- so engines outside Snowflake (see scripts/read_iceberg_from_outside.py) read
-- the exact same numbers as Snowsight.

SELECT *
FROM SEMANTIC_VIEW(
    {{ ref('sem_orders') }}
    METRICS
        orders.total_revenue,
        orders.order_count,
        orders.average_order_value
    DIMENSIONS
        customers.region,
        customers.segment
)
ORDER BY region, segment
