SELECT
  UPPER(TRIM(account_id))                             AS account_id,
  UPPER(TRIM(customer_id))                            AS customer_id,
  TRIM(account_name)                                  AS account_name,
  TRIM(region)                                        AS region,
  TRIM(account_owner)                                 AS account_owner,
  TRIM(segment)                                       AS segment,
  UPPER(TRIM(active_flag)) IN ('TRUE', 'T', 'Y', '1') AS is_active
FROM {{ source('raw', 'salesforce_accounts') }}