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
  FROM {{ ref('int_orders_valid') }} o
  LEFT JOIN {{ ref('stg_accounts') }} c ON o.customer_id = c.customer_id
  LEFT JOIN {{ ref('stg_products') }} p ON o.product_id  = p.product_id
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
FROM base