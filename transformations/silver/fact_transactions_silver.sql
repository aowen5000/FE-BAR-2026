-- ============================================================================
-- Pipeline: FE BAR Bronze Silver AutoLoader Pipeline
-- Layer:    Silver
-- Table:    fact_transactions_silver
-- Upstream: fact_transactions_bronze
-- Features: Dedup by txn_id (keep latest by timestamp),
--           drop NULL txn_id and customer_id,
--           row filter: amounts > $10,000 visible only to PII group
-- Workspace: fevm-workshop-guy
-- Date:     2026-10-14
-- Genie Conversation Thread ID: 2172058462486781
-- Branch:   feature/bronze-silver-autoloader-pipeline
-- ============================================================================

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
