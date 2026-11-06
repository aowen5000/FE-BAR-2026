-- =============================================================================
-- uc_app_grants.sql  (Step 9, 2026-11-04)  workspace fevm-workshop-guy
-- Unity Catalog grants for the Databricks App fe-bar-fraud-triage service principal
--   name:            app-1xzuu6 fe-bar-fraud-triage
--   application ID:  8f239f44-078a-4f8f-90f1-4c1b0bcdc26c
--   numeric ID:      72319122930742
-- Purpose: Ask Genie. With app authorization, Genie runs SQL as this SP, so it
-- needs SELECT on exactly the Genie space sources and nothing else.
-- Idempotent: GRANT of an existing privilege is a no-op.
-- Genie space CAN_RUN and warehouse CAN_USE come from the app resources, not SQL.
-- Deliberately NOT granted: scored_transactions, txn_features_gold,
-- customer_risk_profile_gold, any silver table, fe_bar_lakebase.fraud / fraud_gov / cases.
-- The SP is not added to any group (pii / non_pii).
-- =============================================================================

-- fe_bar_lakebase.fraud_dash (Genie sources 1-6)
GRANT USE CATALOG ON CATALOG fe_bar_lakebase TO `8f239f44-078a-4f8f-90f1-4c1b0bcdc26c`;
GRANT USE SCHEMA ON SCHEMA fe_bar_lakebase.fraud_dash TO `8f239f44-078a-4f8f-90f1-4c1b0bcdc26c`;
GRANT SELECT ON TABLE fe_bar_lakebase.fraud_dash.triage_queue        TO `8f239f44-078a-4f8f-90f1-4c1b0bcdc26c`;
GRANT SELECT ON TABLE fe_bar_lakebase.fraud_dash.case_summary        TO `8f239f44-078a-4f8f-90f1-4c1b0bcdc26c`;
GRANT SELECT ON TABLE fe_bar_lakebase.fraud_dash.case_actions_daily  TO `8f239f44-078a-4f8f-90f1-4c1b0bcdc26c`;
GRANT SELECT ON TABLE fe_bar_lakebase.fraud_dash.exposure            TO `8f239f44-078a-4f8f-90f1-4c1b0bcdc26c`;
GRANT SELECT ON TABLE fe_bar_lakebase.fraud_dash.baseline_comparison TO `8f239f44-078a-4f8f-90f1-4c1b0bcdc26c`;
GRANT SELECT ON TABLE fe_bar_lakebase.fraud_dash.score_distribution  TO `8f239f44-078a-4f8f-90f1-4c1b0bcdc26c`;

-- workshop_guy_catalog.fe_bar_a0.risk_score_calibration (Genie source 7)
GRANT USE CATALOG ON CATALOG workshop_guy_catalog TO `8f239f44-078a-4f8f-90f1-4c1b0bcdc26c`;
GRANT USE SCHEMA ON SCHEMA workshop_guy_catalog.fe_bar_a0 TO `8f239f44-078a-4f8f-90f1-4c1b0bcdc26c`;
GRANT SELECT ON TABLE workshop_guy_catalog.fe_bar_a0.risk_score_calibration TO `8f239f44-078a-4f8f-90f1-4c1b0bcdc26c`;
