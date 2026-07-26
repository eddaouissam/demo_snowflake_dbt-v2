-- Staging layer : light cleaning + renaming only. One staging model per raw entity.

SELECT
    customer_id,
    customer_name,
    UPPER(region)               AS region,
    segment,
    CAST(signup_date AS DATE)   AS signup_date
FROM {{ ref('raw_customers') }}
