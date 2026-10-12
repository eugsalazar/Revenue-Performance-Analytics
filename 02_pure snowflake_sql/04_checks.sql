-- =====================================================
-- 06. CHECKS: reconciliation and data-quality queries
-- =====================================================

USE DATABASE REVENUE_DB;

SELECT 'oracle_orders' AS tbl, COUNT(*) AS n FROM raw.oracle_orders
UNION ALL SELECT 'salesforce_accounts', COUNT(*) FROM raw.salesforce_accounts
UNION ALL SELECT 'adaptive_forecast',   COUNT(*) FROM raw.adaptive_forecast
UNION ALL SELECT 'product_master',      COUNT(*) FROM raw.product_master;


--Reconciliation: raw = valid + quarantined
SELECT (SELECT COUNT(*) FROM raw.oracle_orders) AS raw_rows,
       (SELECT COUNT(*) FROM clean.orders_valid)                 AS valid_rows,
       (SELECT COUNT(*) FROM clean.orders_quarantine)            AS quarantined_rows;


SELECT order_id, reject_reason FROM clean.orders_quarantine ORDER BY order_id;


select count(*) from clean.orders_enriched;

select * from clean.orders_enriched;

-- the orphans should show up as UNKNOWN
SELECT order_id, source_customer_id, region, source_product_id, product_key, gross_amount
FROM clean.orders_enriched
WHERE is_orphan_customer OR is_orphan_product;

SELECT order_status, COUNT(*) AS n, COUNT(on_time_flag) AS evaluated, AVG(on_time_flag) AS otd
FROM clean.orders_enriched
GROUP BY order_status;

select * from clean.actuals_monthly;

SELECT SUM(actual_revenue) FROM clean.actuals_monthly
union all
SELECT SUM(actual_revenue) FROM clean.orders_enriched;


SHOW OBJECTS IN SCHEMA REVENUE_DB.CLEAN;  
SHOW OBJECTS IN SCHEMA REVENUE_DB.RAW;  

  SELECT SUM(estimated_gross_margin), SUM(revenue_with_cost),
       SUM(estimated_gross_margin) / SUM(revenue_with_cost)
FROM REVENUE_DB.ANALYTICS.mart_revenue_performance;


SELECT SUM(actual_revenue)   FROM REVENUE_DB.ANALYTICS.mart_revenue_performance;  -- 6,168,239.01
SELECT SUM(forecast_revenue) FROM REVENUE_DB.ANALYTICS.mart_revenue_performance;  -- 39,254,559.41

SELECT month_start, region, product_id, COUNT(*)
FROM REVENUE_DB.ANALYTICS.mart_revenue_performance
GROUP BY 1, 2, 3 HAVING COUNT(*) > 1;   -- 0 rows

SELECT COUNT(*) FROM REVENUE_DB.CLEAN.orders_enriched;              
SELECT SUM(actual_revenue) FROM REVENUE_DB.CLEAN.actuals_monthly;  