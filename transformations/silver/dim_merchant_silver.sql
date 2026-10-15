-- ============================================================================
-- Pipeline: FE BAR Bronze Silver AutoLoader Pipeline
-- Layer:    Silver
-- Table:    dim_merchant_silver
-- Upstream: dim_merchant_bronze
-- Features: Dedup by merchant_id, drop NULL merchant_id
-- Workspace: fevm-workshop-guy
-- Date:     2026-10-14
-- Genie Conversation Thread ID: 2172058462486781
-- Branch:   feature/bronze-silver-autoloader-pipeline
-- ============================================================================

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
