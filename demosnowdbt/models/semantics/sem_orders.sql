{{ config(materialized='semantic_view') }}

-- Semantic layer : a native Snowflake SEMANTIC VIEW materialized by dbt via
-- the Snowflake-Labs/dbt_semantic_view package.
--
-- This is NOT a SELECT statement. The model body follows the
-- CREATE SEMANTIC VIEW syntax (TABLES / RELATIONSHIPS / FACTS /
-- DIMENSIONS / METRICS) and the package handles the DDL.
-- Docs : https://docs.snowflake.com/en/sql-reference/sql/create-semantic-view

TABLES (
    orders AS {{ ref('fct_orders') }}
        PRIMARY KEY (order_id)
        WITH SYNONYMS ('sales', 'transactions')
        COMMENT = 'One row per order',
    customers AS {{ ref('dim_customers') }}
        PRIMARY KEY (customer_id)
        WITH SYNONYMS ('clients', 'accounts')
        COMMENT = 'One row per customer'
)

RELATIONSHIPS (
    orders_to_customers AS
        orders (customer_id) REFERENCES customers
)

FACTS (
    orders.order_amount AS order_amount
        COMMENT = 'Gross amount of the order',
    orders.recognized_amount AS recognized_amount
        COMMENT = 'Amount counted as revenue (completed orders only)'
)

DIMENSIONS (
    orders.order_date AS order_date
        COMMENT = 'Date the order was placed',
    orders.order_status AS order_status
        WITH SYNONYMS ('state')
        COMMENT = 'completed, returned or cancelled',
    customers.customer_name AS customer_name,
    customers.region AS region
        WITH SYNONYMS ('geo', 'zone')
        COMMENT = 'Sales region : AMER, EMEA or APAC',
    customers.segment AS segment
        COMMENT = 'Customer segment : Enterprise, Mid-Market or SMB'
)

METRICS (
    orders.total_revenue AS SUM(orders.recognized_amount)
        WITH SYNONYMS ('revenue', 'sales total')
        COMMENT = 'Sum of recognized amounts (completed orders only)',
    orders.gross_order_value AS SUM(orders.order_amount)
        COMMENT = 'Sum of all order amounts regardless of status',
    orders.order_count AS COUNT(orders.order_id)
        COMMENT = 'Number of orders',
    orders.average_order_value AS AVG(orders.order_amount)
        WITH SYNONYMS ('AOV')
        COMMENT = 'Average gross amount per order'
)

COMMENT = 'Order analytics semantic view : governed metrics over fct_orders and dim_customers'
