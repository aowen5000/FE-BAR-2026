-- ============================================================================
-- Pipeline: FE BAR Bronze Silver AutoLoader Pipeline
-- Layer:    Silver
-- Table:    fact_prior_fraud_cases_silver
-- Upstream: fact_prior_fraud_cases_bronze
-- Features: Dedup by case_id (keep latest by resolution_date),
--           drop NULL case_id, txn_id, and customer_id
-- Workspace: fevm-workshop-guy
-- Date:     2026-10-14
-- Genie Conversation Thread ID: 2172058462486781
-- Branch:   feature/bronze-silver-autoloader-pipeline
-- ============================================================================

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
