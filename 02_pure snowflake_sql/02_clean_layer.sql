-- =====================================================
-- 03. CLEAN: staging views, validation, quarantine
-- =====================================================

USE SCHEMA REVENUE_DB.CLEAN;

-- 1) Typed + standardized view: one row per raw row, nothing removed here
CREATE OR REPLACE VIEW REVENUE_DB.CLEAN.stg_orders AS
SELECT
  UPPER(TRIM(order_id))                                AS order_id,
  UPPER(TRIM(customer_id))                             AS customer_id,
  UPPER(TRIM(product_id))                              AS product_id,
  TRY_TO_DATE(NULLIF(TRIM(order_date), ''))            AS order_date,
  TRY_TO_DATE(NULLIF(TRIM(promised_delivery_date), '')) AS promised_delivery_date,
  TRY_TO_DATE(NULLIF(TRIM(actual_delivery_date), ''))  AS actual_delivery_date,
  TRY_TO_NUMBER(NULLIF(TRIM(quantity), ''), 18, 0)     AS quantity,
  TRY_TO_NUMBER(NULLIF(TRIM(unit_price), ''), 18, 2)   AS unit_price,
  TRIM(plant_location)                                 AS plant_location,
  UPPER(TRIM(order_status))                            AS order_status,
  _source_file, _loaded_at
FROM REVENUE_DB.RAW.oracle_orders;

-- 2) Verdict per row: every raw row gets a reject reason or NULL
CREATE OR REPLACE TABLE REVENUE_DB.CLEAN.orders_validated AS
WITH s AS (
  SELECT *,
    HASH(customer_id, product_id, order_date, promised_delivery_date, actual_delivery_date,
         quantity, unit_price, plant_location, order_status) AS payload_hash
  FROM stg_orders
),
v AS (
  SELECT order_id, COUNT(DISTINCT payload_hash) AS n_payloads
  FROM s GROUP BY order_id
)
SELECT
  s.*,
  NULLIF(ARRAY_TO_STRING(ARRAY_CONSTRUCT_COMPACT(
    IFF(v.n_payloads > 1,                              'CONFLICTING_DUPLICATE', NULL),
    IFF(s.order_date IS NULL,                          'MISSING_ORDER_DATE',    NULL),
    IFF(s.quantity IS NULL OR s.quantity <= 0,         'INVALID_QUANTITY',      NULL),
    IFF(s.unit_price IS NULL OR s.unit_price <= 0,     'INVALID_UNIT_PRICE',    NULL)
  ), ', '), '') AS reject_reason
FROM s JOIN v USING (order_id);

-- 3) Split
CREATE OR REPLACE VIEW REVENUE_DB.CLEAN.orders_valid      AS SELECT * FROM orders_validated WHERE reject_reason IS NULL;
CREATE OR REPLACE VIEW REVENUE_DB.CLEAN.orders_quarantine AS SELECT * FROM orders_validated WHERE reject_reason IS NOT NULL;


--stg_accounts
CREATE OR REPLACE VIEW REVENUE_DB.CLEAN.stg_accounts AS
SELECT
  UPPER(TRIM(account_id))                          AS account_id,
  UPPER(TRIM(customer_id))                         AS customer_id,
  TRIM(account_name)                               AS account_name,
  TRIM(region)                                     AS region,
  TRIM(account_owner)                              AS account_owner,
  TRIM(segment)                                    AS segment,
  UPPER(TRIM(active_flag)) IN ('TRUE', 'T', 'Y', '1') AS is_active
FROM REVENUE_DB.RAW.salesforce_accounts;

--stg_prod
CREATE OR REPLACE VIEW REVENUE_DB.CLEAN.stg_products AS
SELECT
  UPPER(TRIM(product_id))                          AS product_id,
  TRIM(product_name)                               AS product_name,
  TRIM(product_family)                             AS product_family,
  TRIM(lifecycle_status)                           AS lifecycle_status,
  TRY_TO_NUMBER(NULLIF(TRIM(standard_cost), ''), 18, 2) AS STANDARD_COST
FROM REVENUE_DB.RAW.product_master;

--stg_forecst
CREATE OR REPLACE VIEW REVENUE_DB.CLEAN.stg_forecast AS
SELECT
  UPPER(TRIM(forecast_id))                          AS forecast_id,
  UPPER(TRIM(product_id))                           AS product_id,
  TRIM(region)                                      AS region,
  TRY_TO_DATE(NULLIF(TRIM(forecast_month), ''))     AS forecast_month,
  TRY_TO_NUMBER(NULLIF(TRIM(forecast_revenue), ''), 18, 2)  AS forecast_revenue,
  TRY_TO_NUMBER(NULLIF(TRIM(forecast_quantity), ''), 18, 0)  AS forecast_quantity
FROM REVENUE_DB.RAW.adaptive_forecast;


-- =====================================================
-- 04. CLEAN: orders_enriched, actuals_monthly
-- =====================================================

CREATE OR REPLACE VIEW REVENUE_DB.CLEAN.orders_enriched AS
WITH base AS (
  SELECT
    o.order_id,
    o.customer_id                                   AS source_customer_id,
    o.product_id                                    AS source_product_id,
    COALESCE(c.customer_id, 'UNKNOWN')              AS customer_key,
    COALESCE(c.region, 'UNKNOWN')                   AS region,
    COALESCE(p.product_id, 'UNKNOWN')               AS product_key,
    o.order_date,
    DATE_TRUNC('month', o.order_date)               AS order_month,
    o.promised_delivery_date,
    o.actual_delivery_date,
    o.order_status,
    o.quantity,
    o.unit_price,
    o.quantity * o.unit_price                       AS gross_amount,
    IFF(o.order_status = 'SHIPPED', o.quantity * o.unit_price, 0) AS actual_revenue,
    p.standard_cost,
    IFF(o.order_status = 'SHIPPED' AND p.standard_cost IS NOT NULL,
        o.quantity * p.standard_cost, NULL)         AS estimated_cogs,
    (c.customer_id IS NULL)                         AS is_orphan_customer,
    (p.product_id  IS NULL)                         AS is_orphan_product,
    (o.order_status = 'CANCELLED' AND o.actual_delivery_date IS NOT NULL) AS is_cancelled_with_delivery_date,
    (o.actual_delivery_date < o.order_date)         AS is_delivery_before_order,
    CASE
      WHEN o.order_status = 'SHIPPED'
       AND o.actual_delivery_date   IS NOT NULL
       AND o.promised_delivery_date IS NOT NULL
       AND o.actual_delivery_date >= o.order_date
      THEN IFF(o.actual_delivery_date <= o.promised_delivery_date, 1, 0)
    END AS on_time_flag,
    CASE
      WHEN o.order_status = 'SHIPPED'
       AND o.actual_delivery_date   IS NOT NULL
       AND o.promised_delivery_date IS NOT NULL
       AND o.actual_delivery_date >= o.order_date
      THEN DATEDIFF('day', o.promised_delivery_date, o.actual_delivery_date)
    END AS delay_days
  FROM REVENUE_DB.CLEAN.orders_valid o
  LEFT JOIN REVENUE_DB.CLEAN.stg_accounts c ON o.customer_id = c.customer_id
  LEFT JOIN REVENUE_DB.CLEAN.stg_products p ON o.product_id  = p.product_id
)
SELECT
  *,
  CASE
    WHEN order_status = 'CANCELLED' THEN 'CANCELLED'
    WHEN order_status = 'OPEN'      THEN 'OPEN'
    WHEN on_time_flag = 1           THEN 'ON_TIME'
    WHEN on_time_flag = 0           THEN 'LATE'
    ELSE 'NOT_EVALUATED'
  END AS delivery_status
FROM base;


CREATE OR REPLACE VIEW REVENUE_DB.CLEAN.actuals_monthly AS
SELECT
  order_month,
  region,
  product_key,
  COUNT_IF(order_status = 'SHIPPED')                      AS shipped_order_count,
  SUM(IFF(order_status = 'SHIPPED', quantity, 0))         AS actual_quantity,
  SUM(actual_revenue)                                     AS actual_revenue,
  SUM(estimated_cogs)                                     AS estimated_cogs,
  SUM(IFF(estimated_cogs IS NOT NULL, actual_revenue, 0)) AS revenue_with_cost,
  COUNT(on_time_flag)                                     AS delivery_evaluated_orders,
  SUM(on_time_flag)                                       AS on_time_orders,
  COUNT_IF(delivery_status = 'LATE')                      AS late_orders,
  SUM(delay_days)                                         AS sum_delay_days,
  COUNT_IF(delivery_status = 'NOT_EVALUATED')             AS not_evaluated_orders,
  COUNT_IF(order_status = 'OPEN')                         AS open_order_count,
  SUM(IFF(order_status = 'OPEN', gross_amount, 0))        AS open_order_value,
  COUNT_IF(order_status = 'CANCELLED')                    AS cancelled_order_count,
  SUM(IFF(order_status = 'CANCELLED', gross_amount, 0))   AS cancelled_order_value
FROM REVENUE_DB.CLEAN.orders_enriched
GROUP BY order_month, region, product_key;

