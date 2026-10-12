SELECT
  UPPER(TRIM(order_id))                                 AS order_id,
  UPPER(TRIM(customer_id))                              AS customer_id,
  UPPER(TRIM(product_id))                               AS product_id,
  TRY_TO_DATE(NULLIF(TRIM(order_date), ''))             AS order_date,
  TRY_TO_DATE(NULLIF(TRIM(promised_delivery_date), '')) AS promised_delivery_date,
  TRY_TO_DATE(NULLIF(TRIM(actual_delivery_date), ''))   AS actual_delivery_date,
  TRY_TO_NUMBER(NULLIF(TRIM(quantity), ''), 18, 0)      AS quantity,
  TRY_TO_NUMBER(NULLIF(TRIM(unit_price), ''), 18, 2)    AS unit_price,
  TRIM(plant_location)                                  AS plant_location,
  UPPER(TRIM(order_status))                             AS order_status,
  _source_file,
  _loaded_at
FROM {{ source('raw', 'oracle_orders') }}