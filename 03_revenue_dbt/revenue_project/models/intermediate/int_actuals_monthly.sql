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
FROM {{ ref('int_orders_enriched') }}
GROUP BY order_month, region, product_key