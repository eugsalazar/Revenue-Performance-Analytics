SELECT
  UPPER(TRIM(forecast_id))                          AS forecast_id,
  UPPER(TRIM(product_id))                           AS product_id,
  TRIM(region)                                      AS region,
  TRY_TO_DATE(NULLIF(TRIM(forecast_month), ''))     AS forecast_month,
  TRY_TO_NUMBER(NULLIF(TRIM(forecast_revenue), ''), 18, 2)  AS forecast_revenue,
  TRY_TO_NUMBER(NULLIF(TRIM(forecast_quantity), ''), 18, 0)  AS forecast_quantity
FROM {{ source('raw', 'adaptive_forecast') }}