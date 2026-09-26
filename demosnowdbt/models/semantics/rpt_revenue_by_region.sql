{{ config(materialized='table') }}

-- Downstream consumption : a regular dbt model that queries the semantic
-- view with SEMANTIC_VIEW(...). The metrics are computed by Snowflake from
-- the governed definitions — no aggregation logic is duplicated here.

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
