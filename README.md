# Revenue Performance Analytics on Snowflake by Eugenio Salazar

Snowflake solution for reporting on **actual revenue, forecast revenue, revenue variance, delivery performance and estimated gross margin**, built from four source extracts (Oracle orders, Salesforce accounts, Adaptive forecast, product master).

Final output: `REVENUE_DB.ANALYTICS.mart_revenue_performance`.

---

## 1\. Architecture

CSV files \-\> internal stage \-\> COPY INTO \-\> RAW (VARCHAR) \-\> CLEAN (typed, validated, enriched) \-\> ANALYTICS (mart)

| Layer | Schema | What it does |
| :---- | :---- | :---- |
| Source | CSV extracts | Oracle orders, Salesforce accounts, Adaptive forecast, product master |
| Ingestion | `RAW` | `COPY INTO` from the stage. Every business column is `VARCHAR`, plus `_source_file` and `_loaded_at`, so a bad value never fails the load |
| Transformation | `CLEAN` | Typed views (`TRY_TO_*`), one verdict per row, quarantine, joins with reference data, delivery and margin logic, aggregation to the reporting grain |
| Analytical | `ANALYTICS` | `mart_revenue_performance` |

**Assumptions**

1. `customer_id` is the business key shared by Oracle and Salesforce (`account_id` is Salesforce-internal and is not used for joins).  
2. Orders carry no region, so the region of an order is the region of its Salesforce account.  
3. **Actual revenue** \= `quantity * unit_price` of `SHIPPED` orders. `OPEN` is backlog and `CANCELLED` is excluded.  
4. Revenue is reported in the month of `order_date`, the only date present on every order.  
5. Gross margin uses `standard_cost` from the product master, so it is an **estimate**.  
6. The data has no currency; all amounts are treated as one currency.  
7. A quantity of zero or below is invalid, not a return (there is no return indicator in the data).

---

## 2\. Data model

| Object | Grain |
| :---- | :---- |
| `CLEAN.orders_enriched` | one row per valid `order_id` |
| `CLEAN.stg_forecast` | forecast month x product x region |
| `CLEAN.actuals_monthly` | order month x region x product |
| `ANALYTICS.mart_revenue_performance` | **month x region x product** (the forecast grain) |

**Granularity difference.** Orders are at order level and have no region. The forecast is at month x product x region and has no customer. I aggregate the orders **up** to month x region x product (`actuals_monthly`) and join the forecast there, 1 to 1\. The forecast is never pushed down to orders: it would be duplicated or need an arbitrary allocation rule. The trade-off is that forecast-vs-actual is not available by customer.

`orders_enriched` keeps both the original ID (`source_customer_id`, `source_product_id`) and the conformed key (`customer_key`, `product_key`, `UNKNOWN` when the reference row does not exist), so orphans keep their revenue and can still be investigated.

---

## 3\. Transformations (`/sql`)

| File | Content |
| :---- | :---- |
| `01_setup_and_load.sql` | Database, schemas, file format, stage, RAW tables, `COPY INTO` |
| `02_clean_layer.sql` | `stg_orders`, `orders_validated`, `orders_valid`, `orders_quarantine,stg_accounts`, `stg_products`, `stg_forecast,` Joins, revenue, COGS, delivery metrics, quality flags,  Aggregation to the reporting grain |
| `03_analytics_mart.sql` |  Final mart |
| `04_checks.sql` | Reconciliation and data-quality queries |

**Metric definitions**

| Metric | Definition |
| :---- | :---- |
| Actual revenue | Sum of `quantity * unit_price` for `SHIPPED` orders |
| Forecast revenue | Sum of `forecast_revenue` |
| Revenue variance | `actual_revenue - forecast_revenue`;  |
| Revenue variance % | `Revenue variance / forecast_revenue`;  `NULL` when there is no forecast row |
| Estimated gross margin | `revenue_with_cost - estimated_cogs`, where `estimated_cogs = quantity * standard_cost` |
| Estimated gross margin % | `Estimated gross margin / revenue_with_cost`  |
| On-time delivery % | on-time shipped orders / shipped orders with coherent dates |
| Delay days | `actual_delivery_date - promised_delivery_date` (positive \= late) |

Estimated COGS is `NULL` (not 0\) when a product has no cost, and margin is computed on `revenue_with_cost` so orders without cost do not inflate the margin.

---

## 4\. Data quality

Every raw order gets a verdict in `orders_validated` (`reject_reason`). Nothing is deleted: **raw rows \= valid \+ quarantined**.

| Issue | Evidence | Handling | Reason |
| :---- | :---- | :---- | :---- |
| Conflicting duplicate | `ORD00005` appears twice (quantity 31 vs 99\) | Quarantine both versions | No timestamp or version in the source to choose the correct one |
| Invalid quantity | `ORD90103` (-15), `ORD90104` (0) | Quarantine | Not a valid sale; no return indicator exists |
| Missing unit price | `ORD90106` | Quarantine | Revenue cannot be calculated |
| Missing order date | `ORD90107` | Quarantine | Cannot be assigned to a reporting month |
| Orphan customer | `ORD90101` \-\> `CUST999` | Keep as `UNKNOWN` | Real sale; dropping it would break reconciliation with the ERP |
| Orphan product | `ORD90102` \-\> `PROD999` | Keep as `UNKNOWN`; margin `NULL` | Same; no cost available |
| Cancelled with delivery date | All 13 cancelled orders | Keep, ignore the date | A cancelled order was not delivered |
| Delivery before order | `ORD90105` | Keep revenue, delivery metrics `NULL` | Date is unreliable and would distort on-time % |
| Forecast gap | `PROD001` / `LATAM` / 2025-01 missing (`FCST00001` absent) | Documented; no row in the mart | Dense grid expected 288 rows, found 287 |

**Reconciliation controls (all executed in Snowflake)**

| Control | Result |
| :---- | :---- |
| Raw rows loaded | 128 / 20 / 287 / 12 (matches the source files) |
| Orders: raw \= valid \+ quarantined | 128 \= 122 \+ 6 |
| `orders_enriched` row count (no join fan-out) | 122 |
| Actual revenue: orders \= monthly aggregate \= mart | 6,168,239.01 |
| Forecast revenue in the mart | 39,254,559.41 |
| Mart grain unique (month x region x product) | 0 duplicates |
| Estimated gross margin | 3,152,721.19 on 6,116,995.48 \= 51.54% |
| On-time delivery | 33.3% (84 shipped orders evaluated) |

**Open finding.** Total forecast (39.25M) is about 6 times the actual shipped revenue (6.17M). I did not adjust either figure. It needs confirmation with the business (different scope, units or a sample-data artifact) before variance numbers are used.

---

## 5\. Key decisions, trade-offs and enhancements

| Decision | Trade-off |
| :---- | :---- |
| Quarantine instead of delete or "fix" | Revenue is understated until a steward resolves the rows (for example `ORD00005`), but nothing is lost and it is auditable |
| Quarantine both versions of `ORD00005` | A source `updated_at` would allow a deterministic choice |
| Keep orphans as `UNKNOWN` | Appears as region/product `UNKNOWN` in reports; filterable |
| Variance `NULL` when there is no forecast | Zero would claim "forecast was 0" |
| Revenue by order month | Not accounting-grade recognition; delivery month is the alternative |
| Standard cost for margin | Ignores actual cost, freight and rebates |
| `[CONFIRM: DIV0 or NULLIF]` for ratios | `DIV0` returns 0 when the denominator is 0, which can read as "0% on-time" when there were no deliveries to evaluate |
| Views for CLEAN, table for the mart | Fine at this volume; larger volumes need materialization and incremental logic |

**What I would improve in production**

- Least-privilege roles (I used `ACCOUNTADMIN` on a trial account), separate warehouses for load and transform.  
- External stage plus Snowpipe, and incremental processing (Streams and Tasks).  
- dbt with tests (`unique`, `not_null`, `relationships`, `accepted_values`), lineage docs and CI/CD.  
- Source `updated_at` to resolve duplicates; SCD2 for customer and product dimensions (standard cost by date).  
- Monitoring: freshness, volume and quarantine-rate alerts.  
- Power BI semantic model and a data-quality dashboard.

## 6. How to run

### Option A: Pure Snowflake Solution (Primary)
1. Upload the four CSV source files to your Snowflake internal stage `@stg_landing`.
2. Open a Snowflake Worksheet and execute the SQL scripts located in the `/sql` directory in strict numeric order:
   - `01_setup_and_load.sql` (DDL and Ingestion via COPY INTO)
   - `02_clean_layer.sql` (Data Quality Framework, transformations, and aggregation)
   - `03_analytics_mart.sql` (Final Mart materialization)
   - `04_checks.sql` (Reconciliation and audit queries)
   *Note: Ensure you use the "Run All" feature or execute statements sequentially, verifying `USE SCHEMA` at the top of each file.*

### Option B: Modern Data Stack Alternative (dbt-ready)
The repository contains the corresponding configuration files to orchestrate this entire pipeline through dbt if preferred by the evaluation team:
1. Ensure your source data is loaded into the `RAW` schema.
2. Install the project dependencies:
   ```bash
   dbt deps
   ```
3. Verify your connection target to Snowflake (`profiles.yml`):
   ```bash
   dbt debug
   ```
4. Build, test, and materialize the entire pipeline (Staging, Intermediate, and Marts) with a single command:
   ```bash
   dbt build
   ```

