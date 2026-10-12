SELECT
  UPPER(TRIM(product_id))                          AS product_id,
  TRIM(product_name)                               AS product_name,
  TRIM(product_family)                             AS product_family,
  TRIM(lifecycle_status)                           AS lifecycle_status,
  TRY_TO_NUMBER(NULLIF(TRIM(standard_cost), ''), 18, 2) AS STANDARD_COST
FROM {{ source('raw', 'product_master') }}