with orders as (
    select * from {{ ref('stg_tpch__orders') }}
),

lineitems as (
    select * from {{ ref('stg_tpch__lineitems') }}
),

order_items as (
    select
        orders.order_key,
        orders.customer_key,
        orders.order_status,
        orders.order_date,
        orders.order_priority,
        sum(lineitems.extended_price) as gross_amount,
        sum(lineitems.extended_price * (1 - lineitems.discount)) as net_amount,
        sum(lineitems.quantity) as total_quantity,
        count(lineitems.line_number) as line_count
    from orders
    left join lineitems on orders.order_key = lineitems.order_key
    group by 1, 2, 3, 4, 5
)

select * from order_items
