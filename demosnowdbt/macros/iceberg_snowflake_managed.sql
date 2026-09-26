{#-
    Workaround : dbt-snowflake + Snowflake storage for Iceberg (SNOWFLAKE_MANAGED)
    -------------------------------------------------------------------------
    dbt-snowflake (1.9 -> 1.12 at least) ALWAYS adds a `base_location = '...'`
    clause to CREATE ICEBERG TABLE. Snowflake-managed storage rejects it :

        BASE_LOCATION property is not supported for Iceberg tables
        using Snowflake Managed Storage.

    Tracked here : https://github.com/dbt-labs/dbt-adapters/issues/1911
    (dbt Fusion 2.0 already omits it, dbt Core doesn't yet.)

    Instead of copy-pasting the whole adapter macro (and drifting from it on
    every dbt upgrade), this override WRAPS the original one : it renders the
    adapter's DDL untouched, then strips the base_location clause only when
    the model targets SNOWFLAKE_MANAGED. Tables on a real external volume
    (S3 / Azure / GCS) keep their base_location.

    Root-project macros take precedence over adapter macros with the same
    name, so dbt picks this one up automatically. Delete this file once the
    adapter fix ships in the dbt version your dbt Project runs on.
-#}

{% macro snowflake__create_table_built_in_sql(relation, compiled_code) -%}

    {%- set original_ddl = dbt.snowflake__create_table_built_in_sql(relation, compiled_code) -%}
    {%- set catalog_relation = adapter.build_catalog_relation(config.model) -%}
    {%- set external_volume = (catalog_relation.external_volume or '') | string | upper -%}

    {%- if external_volume == 'SNOWFLAKE_MANAGED' -%}
        {{ modules.re.sub("base_location\s*=\s*'[^']*'", "", original_ddl) }}
    {%- else -%}
        {{ original_ddl }}
    {%- endif -%}

{%- endmacro %}
