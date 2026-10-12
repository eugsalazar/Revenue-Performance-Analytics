WITH s AS (
  SELECT *,
    HASH(customer_id, product_id, order_date, promised_delivery_date, actual_delivery_date,
         quantity, unit_price, plant_location, order_status) AS payload_hash
  FROM {{ ref('stg_orders') }}
),
v AS (
  SELECT order_id, COUNT(DISTINCT payload_hash) AS n_payloads
  FROM s
  GROUP BY order_id
)
SELECT
  s.*,
  NULLIF(ARRAY_TO_STRING(ARRAY_CONSTRUCT_COMPACT(
    IFF(v.n_payloads > 1,                          'CONFLICTING_DUPLICATE', NULL),
    IFF(s.order_date IS NULL,                      'MISSING_ORDER_DATE',    NULL),
    IFF(s.quantity IS NULL OR s.quantity <= 0,     'INVALID_QUANTITY',      NULL),
    IFF(s.unit_price IS NULL OR s.unit_price <= 0, 'INVALID_UNIT_PRICE',    NULL)
  ), ', '), '') AS reject_reason
FROM s
JOIN v USING (order_id)