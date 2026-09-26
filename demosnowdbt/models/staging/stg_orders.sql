-- Staging layer : light cleaning + renaming only. One staging model per raw entity.

SELECT
    order_id,
    customer_id,
    CAST(order_date AS DATE)        AS order_date,
    LOWER(status)                   AS order_status,
    CAST(amount AS NUMBER(12, 2))   AS order_amount
FROM {{ ref('raw_orders') }}
