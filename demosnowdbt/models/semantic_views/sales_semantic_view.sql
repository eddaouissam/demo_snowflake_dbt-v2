{{ config(materialized='semantic_view') }}

tables (
    CUSTOMERS as {{ ref('dim_customers') }} primary key (CUSTOMER_KEY),
    ORDERS as {{ ref('fct_orders') }} primary key (ORDER_KEY)
)
relationships (
    ORDERS_TO_CUSTOMERS as ORDERS(CUSTOMER_KEY) references CUSTOMERS(CUSTOMER_KEY)
)
facts (
    ORDERS.GROSS_AMOUNT as gross_amount,
    ORDERS.NET_AMOUNT as net_amount,
    ORDERS.TOTAL_QUANTITY as total_quantity,
    ORDERS.LINE_COUNT as line_count,
    CUSTOMERS.ACCOUNT_BALANCE as account_balance
)
dimensions (
    CUSTOMERS.CUSTOMER_KEY as customer_key,
    CUSTOMERS.CUSTOMER_NAME as customer_name,
    CUSTOMERS.MARKET_SEGMENT as market_segment,
    CUSTOMERS.NATION_NAME as nation_name,
    CUSTOMERS.REGION_NAME as region_name,
    ORDERS.ORDER_KEY as order_key,
    ORDERS.ORDER_STATUS as order_status,
    ORDERS.ORDER_DATE as order_date,
    ORDERS.ORDER_PRIORITY as order_priority
)
metrics (
    ORDERS.TOTAL_REVENUE as SUM(gross_amount)
        WITH SYNONYMS = ('total sales', 'revenue', 'total gross amount'),
    ORDERS.TOTAL_NET_REVENUE as SUM(net_amount)
        WITH SYNONYMS = ('net sales', 'net revenue'),
    ORDERS.AVG_ORDER_VALUE as AVG(gross_amount)
        WITH SYNONYMS = ('average order value', 'aov'),
    ORDERS.ORDER_COUNT as COUNT(order_key)
        WITH SYNONYMS = ('number of orders', 'total orders'),
    ORDERS.TOTAL_ITEMS_SOLD as SUM(total_quantity)
        WITH SYNONYMS = ('items sold', 'quantity sold')
)
