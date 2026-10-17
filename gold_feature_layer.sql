-- =============================================================================
-- Gold Feature Layer — Fraud Risk Model
-- Pipeline: FE BAR Bronze Silver AutoLoader Pipeline
-- Catalog:  workshop_guy_catalog  |  Schema: fe_bar_a0
-- =============================================================================

-- ---------------------------------------------------------------------------
-- GOLD TABLE 1: txn_features_gold  (one row per transaction)
--   Seeded fraud signal features + behavioural features.
--   CRITICAL: every window/history feature uses RANGE BETWEEN … AND 1 PRECEDING
--   so the current row is NEVER included (no target leakage).
-- ---------------------------------------------------------------------------
CREATE OR REFRESH MATERIALIZED VIEW txn_features_gold (
  CONSTRAINT valid_txn_ts    EXPECT (txn_ts IS NOT NULL)  ON VIOLATION DROP ROW,
  CONSTRAINT positive_amount EXPECT (amount > 0)          ON VIOLATION DROP ROW
)
COMMENT 'Gold layer: transaction-level fraud risk features with no target leakage — one row per transaction'
AS
WITH base AS (
  SELECT
    t.txn_id,
    t.customer_id,
    t.merchant_id,
    CAST(t.`timestamp` AS TIMESTAMP)        AS txn_ts,
    t.amount,
    t.channel,
    t.device_id,
    t.geo_distance_from_home,
    t.is_fraud,
    c.home_region,
    c.risk_segment,
    c.tenure,
    c.avg_monthly_spend,
    m.country       AS merchant_country,
    m.mcc_category,
    m.risk_tier,
    CASE
      WHEN c.home_region IN ('US-East', 'US-West') THEN 'US'
      WHEN c.home_region = 'EU'                    THEN 'UK'
      WHEN c.home_region = 'APAC'                  THEN 'JP'
      ELSE 'BR'
    END AS home_country
  FROM fact_transactions_silver t
  LEFT JOIN dim_customer_silver  c ON t.customer_id = c.customer_id
  LEFT JOIN dim_merchant_silver  m ON t.merchant_id  = m.merchant_id
),
windowed AS (
  SELECT
    *,
    -- Device novelty: first-ever txn on this device for this customer
    ROW_NUMBER() OVER (
      PARTITION BY customer_id, device_id
      ORDER BY txn_ts, txn_id
    ) AS device_seq,

    -- Behavioural: strictly-prior counts (RANGE excludes current row & same-second peers)
    COUNT(*) OVER (
      PARTITION BY customer_id
      ORDER BY unix_seconds(txn_ts)
      RANGE BETWEEN 3600 PRECEDING AND 1 PRECEDING
    ) AS txn_count_1h,

    COUNT(*) OVER (
      PARTITION BY customer_id
      ORDER BY unix_seconds(txn_ts)
      RANGE BETWEEN 86400 PRECEDING AND 1 PRECEDING
    ) AS txn_count_24h,

    -- Customer avg amount over prior 30 days (2 592 000 seconds)
    AVG(amount) OVER (
      PARTITION BY customer_id
      ORDER BY unix_seconds(txn_ts)
      RANGE BETWEEN 2592000 PRECEDING AND 1 PRECEDING
    ) AS cust_avg_amt_30d,

    -- Seconds since previous txn (LAG always looks strictly earlier)
    unix_seconds(txn_ts) - LAG(unix_seconds(txn_ts)) OVER (
      PARTITION BY customer_id
      ORDER BY unix_seconds(txn_ts), txn_id
    ) AS secs_since_prev_txn
  FROM base
)
SELECT
  txn_id,
  customer_id,
  merchant_id,
  txn_ts,

  -- Seeded fraud signal features
  amount,
  CASE WHEN avg_monthly_spend IS NOT NULL AND avg_monthly_spend <> 0
       THEN amount / avg_monthly_spend
       ELSE NULL
  END                                                                        AS amt_to_monthly_spend,
  home_country,
  CAST(CASE WHEN merchant_country <> home_country THEN 1 ELSE 0 END AS INT)  AS is_cross_border,
  geo_distance_from_home,
  CAST(CASE WHEN device_seq = 1           THEN 1 ELSE 0 END AS INT)          AS is_new_device,
  device_id,
  CAST(CASE WHEN channel = 'online'       THEN 1 ELSE 0 END AS INT)          AS is_online,
  channel,
  risk_tier,
  risk_segment,
  merchant_country,

  -- Behavioural features
  txn_count_1h,
  txn_count_24h,
  CASE WHEN cust_avg_amt_30d IS NOT NULL AND cust_avg_amt_30d <> 0
       THEN amount / cust_avg_amt_30d
       ELSE NULL
  END                                                                        AS amt_to_cust_avg_30d,
  secs_since_prev_txn,
  HOUR(txn_ts)                                                               AS hour_of_day,
  CAST(CASE WHEN HOUR(txn_ts) BETWEEN 0 AND 5 THEN 1 ELSE 0 END AS INT)     AS is_night,
  mcc_category,
  tenure,

  -- Label (passthrough, never used as a feature)
  is_fraud
FROM windowed;


-- ---------------------------------------------------------------------------
-- GOLD TABLE 2: customer_risk_profile_gold  (one row per customer)
--   For Lakebase sync and AI agent.  NOT a model input.
--   "Recent" = last 30 days back from MAX(txn_ts) in txn_features_gold
--   (the data is historical / synthetic — do NOT use current_date).
-- ---------------------------------------------------------------------------
CREATE OR REFRESH MATERIALIZED VIEW customer_risk_profile_gold
COMMENT 'Gold layer: per-customer risk profile for Lakebase sync and AI agent — one row per customer (not a model input)'
AS
WITH max_ts AS (
  SELECT MAX(txn_ts) AS global_max_ts
  FROM txn_features_gold
),
recent_txns AS (
  SELECT
    t.customer_id,
    COUNT(*)                              AS txn_count_30d,
    AVG(t.amount)                         AS avg_amount_30d,
    COUNT(DISTINCT t.device_id)           AS distinct_devices_30d,
    COUNT(DISTINCT m.country)             AS distinct_countries_30d,
    SUM(
      CASE WHEN m.country <>
        CASE
          WHEN c.home_region IN ('US-East', 'US-West') THEN 'US'
          WHEN c.home_region = 'EU'                    THEN 'UK'
          WHEN c.home_region = 'APAC'                  THEN 'JP'
          ELSE 'BR'
        END
      THEN 1 ELSE 0 END
    )                                     AS cross_border_txns_30d,
    MAX(CAST(t.`timestamp` AS TIMESTAMP)) AS last_txn_ts
  FROM fact_transactions_silver t
  CROSS JOIN max_ts
  LEFT JOIN dim_customer_silver  c ON t.customer_id = c.customer_id
  LEFT JOIN dim_merchant_silver  m ON t.merchant_id  = m.merchant_id
  WHERE CAST(t.`timestamp` AS TIMESTAMP) >= max_ts.global_max_ts - INTERVAL 30 DAYS
  GROUP BY t.customer_id
),
fraud_cases AS (
  SELECT
    customer_id,
    COUNT(*)                                                              AS prior_case_count,
    COUNT(CASE WHEN investigation_outcome = 'confirmed_fraud' THEN 1 END) AS confirmed_fraud_count
  FROM fact_prior_fraud_cases_silver
  GROUP BY customer_id
)
SELECT
  c.customer_id,
  c.tenure,
  c.home_region,
  c.risk_segment,
  COALESCE(r.txn_count_30d, 0)            AS txn_count_30d,
  COALESCE(r.avg_amount_30d, 0.0)         AS avg_amount_30d,
  COALESCE(r.distinct_devices_30d, 0)     AS distinct_devices_30d,
  COALESCE(r.distinct_countries_30d, 0)   AS distinct_countries_30d,
  COALESCE(r.cross_border_txns_30d, 0)    AS cross_border_txns_30d,
  r.last_txn_ts,
  COALESCE(f.prior_case_count, 0)         AS prior_case_count,
  COALESCE(f.confirmed_fraud_count, 0)    AS confirmed_fraud_count
FROM dim_customer_silver c
LEFT JOIN recent_txns  r ON c.customer_id = r.customer_id
LEFT JOIN fraud_cases  f ON c.customer_id = f.customer_id;
