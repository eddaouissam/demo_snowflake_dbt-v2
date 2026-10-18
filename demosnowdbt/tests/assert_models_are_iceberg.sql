-- Singular test : every model listed below must physically be an Apache
-- Iceberg table in Snowflake. Returns one row per model that is missing or
-- stored as a native table -> the test fails.
--
-- Guards against silent regressions (e.g. someone drops the table_format
-- config or the enable_iceberg_materializations flag).

{%- set iceberg_models = [
    ref('dim_customers'),
    ref('fct_orders'),
    ref('fct_daily_revenue'),
    ref('rpt_revenue_by_region'),
] %}

WITH expected AS (
    {%- for rel in iceberg_models %}
    SELECT '{{ rel.schema | upper }}' AS table_schema, '{{ rel.identifier | upper }}' AS table_name
    {%- if not loop.last %} UNION ALL {% endif %}
    {%- endfor %}
),

actual AS (
    SELECT table_schema, table_name, is_iceberg
    FROM {{ iceberg_models[0].database }}.INFORMATION_SCHEMA.TABLES
)

SELECT
    e.table_schema,
    e.table_name,
    COALESCE(a.is_iceberg, 'MISSING') AS is_iceberg
FROM expected e
LEFT JOIN actual a
    ON  a.table_schema = e.table_schema
    AND a.table_name   = e.table_name
WHERE COALESCE(a.is_iceberg, 'MISSING') <> 'YES'
