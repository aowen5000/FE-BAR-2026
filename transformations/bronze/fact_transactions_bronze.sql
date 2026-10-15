-- ============================================================================
-- Pipeline: FE BAR Bronze Silver AutoLoader Pipeline
-- Layer:    Bronze
-- Table:    fact_transactions_bronze
-- Source:   /Volumes/workshop_guy_catalog/fe_bar_a0/staging/transactions/
-- Workspace: fevm-workshop-guy
-- Date:     2026-10-14
-- Genie Conversation Thread ID: 2172058462486781
-- Branch:   feature/bronze-silver-autoloader-pipeline
-- ============================================================================

CREATE OR REFRESH STREAMING TABLE fact_transactions_bronze
COMMENT "Bronze layer: raw transaction fact data ingested via AutoLoader from UC Volume"
AS SELECT *
FROM STREAM read_files(
  '/Volumes/workshop_guy_catalog/fe_bar_a0/staging/transactions/',
  format => 'json'
);
