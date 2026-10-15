-- ============================================================================
-- Pipeline: FE BAR Bronze Silver AutoLoader Pipeline
-- Layer:    Silver
-- Table:    dim_customer_silver
-- Upstream: dim_customer_bronze
-- Features: Dedup by customer_id, drop NULL customer_id,
--           column mask on avg_monthly_spend (PII group only)
-- Workspace: fevm-workshop-guy
-- Date:     2026-10-14
-- Genie Conversation Thread ID: 2172058462486781
-- Branch:   feature/bronze-silver-autoloader-pipeline
-- ============================================================================

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
