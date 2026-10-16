-- Databricks notebook source

-- MAGIC %md
-- MAGIC # FE BAR Bronze Silver AutoLoader Pipeline
-- MAGIC
-- MAGIC **Pipeline:** FE BAR Bronze Silver AutoLoader Pipeline | **ID:** `c0db28b8-dbd2-432d-99cf-4ea2aea60274`  
-- MAGIC **Catalog:** `workshop_guy_catalog` | **Schema:** `fe_bar_a0`  
-- MAGIC **Workspace:** fevm-workshop-guy | **Date:** 2026-10-14  
-- MAGIC **Branch:** `feature/bronze-silver-autoloader-pipeline`  
-- MAGIC **Genie Conversation ID:** 2172058462486781

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Bronze Layer — Streaming Tables via AutoLoader

-- COMMAND ----------

-- DBTITLE 1,dim_customer_bronze
CREATE OR REFRESH STREAMING TABLE dim_customer_bronze
COMMENT "Bronze layer: raw customer dimension data ingested via AutoLoader from UC Volume"
AS SELECT *
FROM STREAM read_files(
  '/Volumes/workshop_guy_catalog/fe_bar_a0/staging/customers/',
  format => 'json'
);

-- COMMAND ----------

-- DBTITLE 1,dim_merchant_bronze
CREATE OR REFRESH STREAMING TABLE dim_merchant_bronze
COMMENT "Bronze layer: raw merchant dimension data ingested via AutoLoader from UC Volume"
AS SELECT *
FROM STREAM read_files(
  '/Volumes/workshop_guy_catalog/fe_bar_a0/staging/merchants/',
  format => 'json'
);

-- COMMAND ----------

-- DBTITLE 1,fact_transactions_bronze
CREATE OR REFRESH STREAMING TABLE fact_transactions_bronze
COMMENT "Bronze layer: raw transaction fact data ingested via AutoLoader from UC Volume"
AS SELECT *
FROM STREAM read_files(
  '/Volumes/workshop_guy_catalog/fe_bar_a0/staging/transactions/',
  format => 'json'
);

-- COMMAND ----------

-- DBTITLE 1,fact_prior_fraud_cases_bronze
CREATE OR REFRESH STREAMING TABLE fact_prior_fraud_cases_bronze
COMMENT "Bronze layer: raw prior fraud cases data ingested via AutoLoader from UC Volume"
AS SELECT *
FROM STREAM read_files(
  '/Volumes/workshop_guy_catalog/fe_bar_a0/staging/prior_fraud_cases/',
  format => 'json'
);

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Silver Layer — Materialized Views with Dedup, Expectations & FGAC

-- COMMAND ----------

-- DBTITLE 1,dim_customer_silver
CREATE OR REFRESH MATERIALIZED VIEW dim_customer_silver (
  customer_id STRING,
  home_region STRING,
  risk_segment STRING,
  tenure BIGINT,
  avg_monthly_spend DOUBLE MASK workshop_guy_catalog.fe_bar_a0.mask_avg_monthly_spend,
  CONSTRAINT valid_customer_id EXPECT (customer_id IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT "Silver layer: deduplicated customers with column mask on avg_monthly_spend (PII group sees all)"
AS
SELECT customer_id, home_region, risk_segment, tenure, avg_monthly_spend
FROM (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY customer_id) AS rn
  FROM dim_customer_bronze
) WHERE rn = 1;

-- COMMAND ----------

-- DBTITLE 1,dim_merchant_silver
CREATE OR REFRESH MATERIALIZED VIEW dim_merchant_silver (
  CONSTRAINT valid_merchant_id EXPECT (merchant_id IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT "Silver layer: deduplicated merchants with NULL merchant_id rows dropped"
AS
SELECT merchant_id, country, mcc_category, risk_tier
FROM (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY merchant_id ORDER BY merchant_id) AS rn
  FROM dim_merchant_bronze
) WHERE rn = 1;

-- COMMAND ----------

-- DBTITLE 1,fact_transactions_silver
CREATE OR REFRESH MATERIALIZED VIEW fact_transactions_silver (
  CONSTRAINT valid_txn_id EXPECT (txn_id IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT valid_customer_id EXPECT (customer_id IS NOT NULL) ON VIOLATION DROP ROW
)
WITH ROW FILTER workshop_guy_catalog.fe_bar_a0.filter_high_amount_txns ON (amount)
COMMENT "Silver layer: deduplicated transactions; row filter hides amount > 10000 from non-PII users"
AS
SELECT txn_id, customer_id, merchant_id, amount, channel, device_id,
       geo_distance_from_home, is_fraud, `timestamp`
FROM (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY txn_id ORDER BY `timestamp` DESC) AS rn
  FROM fact_transactions_bronze
) WHERE rn = 1;

-- COMMAND ----------

-- DBTITLE 1,fact_prior_fraud_cases_silver
CREATE OR REFRESH MATERIALIZED VIEW fact_prior_fraud_cases_silver (
  CONSTRAINT valid_case_id EXPECT (case_id IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT valid_txn_id EXPECT (txn_id IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT valid_customer_id EXPECT (customer_id IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT "Silver layer: deduplicated prior fraud cases with NULL business keys dropped"
AS
SELECT case_id, customer_id, txn_id, fraud_type, investigation_outcome,
       recovery_amount, resolution_date
FROM (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY case_id ORDER BY resolution_date DESC) AS rn
  FROM fact_prior_fraud_cases_bronze
) WHERE rn = 1;
