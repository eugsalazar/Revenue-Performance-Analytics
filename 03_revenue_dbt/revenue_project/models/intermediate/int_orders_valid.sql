SELECT *
FROM {{ ref('int_orders_validated') }}
WHERE reject_reason IS NULL