-- =====================================================
-- 01. SETUP: warehouse, database, schemas
-- =====================================================

USE ROLE ACCOUNTADMIN; 

--DB structure
CREATE DATABASE IF NOT EXISTS REVENUE_DB;
CREATE SCHEMA IF NOT EXISTS REVENUE_DB.RAW;        -- data exactly as received
CREATE SCHEMA IF NOT EXISTS REVENUE_DB.CLEAN;      -- typed, standardized, validated
CREATE SCHEMA IF NOT EXISTS REVENUE_DB.ANALYTICS;  -- dims, facts, mart

USE SCHEMA REVENUE_DB.RAW;


-- =====================================================
-- 02. RAW: stage, tables, COPY INTO
-- =====================================================

CREATE FILE FORMAT IF NOT EXISTS ff_csv
  TYPE = CSV SKIP_HEADER = 1 FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('', 'NULL') TRIM_SPACE = TRUE;

CREATE STAGE IF NOT EXISTS stg_landing FILE_FORMAT = ff_csv;
LIST @stg_landing;

CREATE OR REPLACE TABLE oracle_orders (
  order_id VARCHAR, customer_id VARCHAR, product_id VARCHAR,
  order_date VARCHAR, promised_delivery_date VARCHAR, actual_delivery_date VARCHAR,
  quantity VARCHAR, unit_price VARCHAR, plant_location VARCHAR, order_status VARCHAR,
  _source_file VARCHAR, _loaded_at TIMESTAMP_NTZ);

CREATE OR REPLACE TABLE salesforce_accounts (
  account_id VARCHAR, customer_id VARCHAR, account_name VARCHAR, region VARCHAR,
  account_owner VARCHAR, segment VARCHAR, active_flag VARCHAR,
  _source_file VARCHAR, _loaded_at TIMESTAMP_NTZ);

CREATE OR REPLACE TABLE adaptive_forecast (
  forecast_id VARCHAR, product_id VARCHAR, region VARCHAR, forecast_month VARCHAR,
  forecast_revenue VARCHAR, forecast_quantity VARCHAR,
  _source_file VARCHAR, _loaded_at TIMESTAMP_NTZ);

CREATE OR REPLACE TABLE product_master (
  product_id VARCHAR, product_name VARCHAR, product_family VARCHAR,
  lifecycle_status VARCHAR, standard_cost VARCHAR,
  _source_file VARCHAR, _loaded_at TIMESTAMP_NTZ);

--Data load to tables
COPY INTO oracle_orders FROM (
  SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9,$10, METADATA$FILENAME, CURRENT_TIMESTAMP()
  FROM @stg_landing/oracle_orders.csv);

COPY INTO salesforce_accounts FROM (
  SELECT $1,$2,$3,$4,$5,$6,$7, METADATA$FILENAME, CURRENT_TIMESTAMP()
  FROM @stg_landing/salesforce_accounts.csv);

COPY INTO adaptive_forecast FROM (
  SELECT $1,$2,$3,$4,$5,$6, METADATA$FILENAME, CURRENT_TIMESTAMP()
  FROM @stg_landing/adaptive_forecast.csv);

COPY INTO product_master FROM (
  SELECT $1,$2,$3,$4,$5, METADATA$FILENAME, CURRENT_TIMESTAMP()
  FROM @stg_landing/product_master.csv);





