{{ config(materialized='table') }}

-- Marts layer : business-ready dimension, the "customers" logical table
-- of the semantic view.

SELECT
    customer_id,
    customer_name,
    region,
    segment,
    signup_date
FROM {{ ref('stg_customers') }}
