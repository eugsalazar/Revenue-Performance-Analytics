SELECT month_start, region, product_id, COUNT(*) AS n
FROM {{ ref('mart_revenue_performance') }}
GROUP BY month_start, region, product_id
HAVING COUNT(*) > 1