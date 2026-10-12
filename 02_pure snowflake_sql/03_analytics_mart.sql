-- =====================================================
-- 05. ANALYTICS: mart_revenue_performance
-- =====================================================
USE SCHEMA REVENUE_DB.ANALYTICS;

CREATE OR REPLACE TABLE REVENUE_DB.ANALYTICS.mart_revenue_performance AS
SELECT
  COALESCE(a.order_month, f.forecast_month)  AS month_start,
  COALESCE(a.region,      f.region)          AS region,
  COALESCE(a.product_key, f.product_id)      AS product_id,
  -- forecast vs actual
  f.forecast_revenue,
  f.forecast_quantity,
  COALESCE(a.actual_revenue, 0)              AS actual_revenue,
  COALESCE(a.actual_quantity, 0)             AS actual_quantity,
  COALESCE(a.actual_revenue, 0) - f.forecast_revenue AS revenue_variance,
  (COALESCE(a.actual_revenue, 0) - f.forecast_revenue)
    / NULLIF(f.forecast_revenue, 0)          AS revenue_variance_pct,
  -- estimated gross margin
  COALESCE(a.revenue_with_cost, 0)           AS revenue_with_cost,
  a.estimated_cogs,
  COALESCE(a.revenue_with_cost, 0) - COALESCE(a.estimated_cogs, 0) AS estimated_gross_margin,
  (COALESCE(a.revenue_with_cost, 0) - COALESCE(a.estimated_cogs, 0))
    / NULLIF(a.revenue_with_cost, 0)         AS estimated_gross_margin_pct,
  -- delivery performance
  COALESCE(a.shipped_order_count, 0)         AS shipped_order_count,
  COALESCE(a.delivery_evaluated_orders, 0)   AS delivery_evaluated_orders,
  COALESCE(a.on_time_orders, 0)              AS on_time_orders,
  COALESCE(a.late_orders, 0)                 AS late_orders,
  COALESCE(a.not_evaluated_orders, 0)        AS not_evaluated_orders,
  COALESCE(a.on_time_orders, 0)
    / NULLIF(a.delivery_evaluated_orders, 0) AS on_time_delivery_pct,
  a.sum_delay_days
    / NULLIF(a.delivery_evaluated_orders, 0) AS avg_delay_days,
  -- backlog and cancellations
  COALESCE(a.open_order_count, 0)            AS open_order_count,
  COALESCE(a.open_order_value, 0)            AS open_order_value,
  COALESCE(a.cancelled_order_count, 0)       AS cancelled_order_count,
  COALESCE(a.cancelled_order_value, 0)       AS cancelled_order_value
FROM REVENUE_DB.CLEAN.actuals_monthly a
FULL OUTER JOIN REVENUE_DB.CLEAN.stg_forecast f
  ON  a.order_month = f.forecast_month
  AND a.region      = f.region
  AND a.product_key = f.product_id;


