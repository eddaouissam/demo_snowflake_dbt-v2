with customers as (
    select * from {{ ref('stg_tpch__customers') }}
),

nations as (
    select * from {{ ref('stg_tpch__nations') }}
),

regions as (
    select * from {{ ref('stg_tpch__regions') }}
),

final as (
    select
        customers.customer_key,
        customers.customer_name,
        customers.address,
        customers.phone,
        customers.account_balance,
        customers.market_segment,
        nations.nation_name,
        regions.region_name
    from customers
    left join nations on customers.nation_key = nations.nation_key
    left join regions on nations.region_key = regions.region_key
)

select * from final
