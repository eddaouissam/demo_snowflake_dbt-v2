-- ============================================
-- SNOWFLAKE ENVIRONMENT SETUP FOR CI/CD DEMO
-- ============================================
-- Run this as ACCOUNTADMIN

USE ROLE ACCOUNTADMIN;

-- ============================================
-- STEP 1 : Create the Role
-- ============================================
CREATE ROLE IF NOT EXISTS DBT_ROLE
  COMMENT = 'Role for dbt CI/CD operations';

-- Grant role to your user (replace with your username)
GRANT ROLE DBT_ROLE TO USER ISSAM;

-- Also grant to SYSADMIN so it stays in the role hierarchy
GRANT ROLE DBT_ROLE TO ROLE SYSADMIN;

-- ============================================
-- STEP 2 : Create the Warehouse
-- ============================================
CREATE WAREHOUSE IF NOT EXISTS DBT_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  COMMENT = 'Warehouse for dbt operations';

GRANT USAGE ON WAREHOUSE DBT_WH TO ROLE DBT_ROLE;
GRANT OPERATE ON WAREHOUSE DBT_WH TO ROLE DBT_ROLE;

-- ============================================
-- STEP 3 : Create Databases
-- ============================================

-- DEV database (used by CI workflow for testing)
CREATE DATABASE IF NOT EXISTS DBT_DEV_DB
  COMMENT = 'Development database for dbt CI/CD';

-- PROD database (used by CD workflow for deployment)
CREATE DATABASE IF NOT EXISTS DBT_PROD_DB
  COMMENT = 'Production database for dbt CI/CD';

-- ============================================
-- STEP 4 : Create Schemas
-- ============================================
CREATE SCHEMA IF NOT EXISTS DBT_DEV_DB.DBT_SCHEMA;
CREATE SCHEMA IF NOT EXISTS DBT_PROD_DB.DBT_SCHEMA;

-- ============================================
-- STEP 5 : Grant Database Permissions
-- ============================================

-- DEV
GRANT ALL ON DATABASE DBT_DEV_DB TO ROLE DBT_ROLE;
GRANT ALL ON SCHEMA DBT_DEV_DB.DBT_SCHEMA TO ROLE DBT_ROLE;
GRANT ALL ON ALL TABLES IN SCHEMA DBT_DEV_DB.DBT_SCHEMA TO ROLE DBT_ROLE;
GRANT ALL ON ALL VIEWS IN SCHEMA DBT_DEV_DB.DBT_SCHEMA TO ROLE DBT_ROLE;
GRANT ALL ON FUTURE TABLES IN SCHEMA DBT_DEV_DB.DBT_SCHEMA TO ROLE DBT_ROLE;
GRANT ALL ON FUTURE VIEWS IN SCHEMA DBT_DEV_DB.DBT_SCHEMA TO ROLE DBT_ROLE;

-- PROD
GRANT ALL ON DATABASE DBT_PROD_DB TO ROLE DBT_ROLE;
GRANT ALL ON SCHEMA DBT_PROD_DB.DBT_SCHEMA TO ROLE DBT_ROLE;
GRANT ALL ON ALL TABLES IN SCHEMA DBT_PROD_DB.DBT_SCHEMA TO ROLE DBT_ROLE;
GRANT ALL ON ALL VIEWS IN SCHEMA DBT_PROD_DB.DBT_SCHEMA TO ROLE DBT_ROLE;
GRANT ALL ON FUTURE TABLES IN SCHEMA DBT_PROD_DB.DBT_SCHEMA TO ROLE DBT_ROLE;
GRANT ALL ON FUTURE VIEWS IN SCHEMA DBT_PROD_DB.DBT_SCHEMA TO ROLE DBT_ROLE;

-- ============================================
-- STEP 6 : Grant dbt Project Permissions
-- ============================================
-- DBT_ROLE needs to create/execute dbt project objects

GRANT CREATE DBT PROJECT ON SCHEMA DBT_DEV_DB.DBT_SCHEMA TO ROLE DBT_ROLE;
GRANT CREATE DBT PROJECT ON SCHEMA DBT_PROD_DB.DBT_SCHEMA TO ROLE DBT_ROLE;

-- ============================================
-- STEP 6b : Semantic View Permissions
-- ============================================
-- SEMANTIC VIEW is a distinct object type : grant creation explicitly
-- (GRANT ALL covers it today, but being explicit survives permission refactors)

GRANT CREATE SEMANTIC VIEW ON SCHEMA DBT_DEV_DB.DBT_SCHEMA TO ROLE DBT_ROLE;
GRANT CREATE SEMANTIC VIEW ON SCHEMA DBT_PROD_DB.DBT_SCHEMA TO ROLE DBT_ROLE;

-- Optional : give an analyst / BI role read access to semantic views only.
-- Semantic views run with owner's rights, so SELECT on the semantic view
-- is enough — no grants needed on the underlying tables.
-- GRANT SELECT ON FUTURE SEMANTIC VIEWS IN SCHEMA DBT_PROD_DB.DBT_SCHEMA TO ROLE ANALYST_ROLE;

-- ============================================
-- STEP 6c : External Access Integration for dbt deps
-- ============================================
-- The dbt_semantic_view package (packages.yml) is installed by `dbt deps`
-- running INSIDE Snowflake. Snowflake needs egress to the dbt package hub :

-- Network rules are schema-level objects, hence the full qualification
CREATE OR REPLACE NETWORK RULE DBT_PROD_DB.DBT_SCHEMA.DBT_HUB_NETWORK_RULE
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = ('hub.getdbt.com', 'codeload.github.com');

-- External access integrations are account-level objects
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION DBT_HUB_INTEGRATION
  ALLOWED_NETWORK_RULES = (DBT_PROD_DB.DBT_SCHEMA.DBT_HUB_NETWORK_RULE)
  ENABLED = TRUE
  COMMENT = 'Allows dbt deps to pull packages from the dbt hub';

GRANT USAGE ON INTEGRATION DBT_HUB_INTEGRATION TO ROLE DBT_ROLE;

-- ============================================
-- STEP 7 : Source Data Access
-- ============================================
-- If your dbt models read from SNOWFLAKE_SAMPLE_DATA or another source DB :

GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE_SAMPLE_DATA TO ROLE DBT_ROLE;

-- If you have another source database, grant SELECT :
-- GRANT USAGE ON DATABASE <SOURCE_DB> TO ROLE DBT_ROLE;
-- GRANT USAGE ON SCHEMA <SOURCE_DB>.<SOURCE_SCHEMA> TO ROLE DBT_ROLE;
-- GRANT SELECT ON ALL TABLES IN SCHEMA <SOURCE_DB>.<SOURCE_SCHEMA> TO ROLE DBT_ROLE;

-- ============================================
-- STEP 8 : Verify Setup
-- ============================================
USE ROLE DBT_ROLE;
USE WAREHOUSE DBT_WH;

-- These should all work without errors
USE DATABASE DBT_DEV_DB;
USE SCHEMA DBT_SCHEMA;

SHOW DATABASES;
SHOW SCHEMAS IN DATABASE DBT_DEV_DB;
SHOW SCHEMAS IN DATABASE DBT_PROD_DB;

SELECT CURRENT_ROLE(), CURRENT_WAREHOUSE(), CURRENT_DATABASE(), CURRENT_SCHEMA();