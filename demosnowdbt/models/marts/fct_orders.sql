{{ config(materialized='table') }}

-- Marts layer : business-ready fact, the "orders" logical table
-- of the semantic view. One row per order.

SELECT
    order_id,
    customer_id,
    order_date,
    order_status,
    order_amount,
    IFF(order_status = 'completed', order_amount, 0) AS recognized_amount
FROM {{ ref('stg_orders') }}
