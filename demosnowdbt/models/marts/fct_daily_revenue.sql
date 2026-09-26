{{ config(
    materialized='incremental',
    unique_key='order_date',
    incremental_strategy='merge',
    on_schema_change='append_new_columns'
) }}

-- Marts layer : daily revenue, built INCREMENTALLY on an Iceberg table.
-- Inherits table_format='iceberg' + external_volume='SNOWFLAKE_MANAGED'
-- from dbt_project.yml (marts folder).
--
-- Why it's here : a MERGE on Iceberg writes new Parquet data files and a new
-- Iceberg snapshot. Nothing changes on the dbt side — same incremental logic
-- as a native table. (dbt still stages the delta in a transient, non-Iceberg
-- temp table before merging ; it's dropped right after.)

SELECT
    order_date,
    COUNT(order_id)                                       AS order_count,
    SUM(recognized_amount)                                AS daily_revenue,
    -- Iceberg timestamps are microsecond precision : cast explicitly
    CAST(CURRENT_TIMESTAMP() AS TIMESTAMP_NTZ(6))         AS _loaded_at
FROM {{ ref('fct_orders') }}

{% if is_incremental() %}
-- Reprocess a 3-day window to catch late-arriving / updated orders
WHERE order_date >= (SELECT DATEADD(day, -3, MAX(order_date)) FROM {{ this }})
{% endif %}

GROUP BY order_date
