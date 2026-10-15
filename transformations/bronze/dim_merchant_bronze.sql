-- ============================================================================
-- Pipeline: FE BAR Bronze Silver AutoLoader Pipeline
-- Layer:    Bronze
-- Table:    dim_merchant_bronze
-- Source:   /Volumes/workshop_guy_catalog/fe_bar_a0/staging/merchants/
-- Workspace: fevm-workshop-guy
-- Date:     2026-10-14
-- Genie Conversation Thread ID: 2172058462486781
-- Branch:   feature/bronze-silver-autoloader-pipeline
-- ============================================================================

CREATE OR REFRESH STREAMING TABLE dim_merchant_bronze
COMMENT "Bronze layer: raw merchant dimension data ingested via AutoLoader from UC Volume"
AS SELECT *
FROM STREAM read_files(
  '/Volumes/workshop_guy_catalog/fe_bar_a0/staging/merchants/',
  format => 'json'
);
