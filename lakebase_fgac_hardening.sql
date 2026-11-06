-- =============================================================================
-- Lakebase FGAC hardening (2026-10-21) for fe_bar_db
-- Workspace fevm-workshop-guy, project fe-bar-fraud-analytics, branch production
-- Idempotent: safe to re-run. Run as alex.owen@databricks.com (databricks_superuser, BYPASSRLS).
-- Never alters the synced tables in schema fraud (read-only, owned by the sync pipeline).
-- The same changes are folded into lakebase_cases_ddl.sql and lakebase_fgac.sql
-- so a fresh rebuild includes them.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Item 1: admin access to the case tables. NO CHANGE NEEDED.
-- Check result: alex.owen@databricks.com has rolbypassrls = true, so FORCE RLS does
-- not hide rows from it (114 cases and 226 actions visible, create + close round trip OK).
-- The admin policy below would only be needed for an admin role WITHOUT BYPASSRLS.
-- It is left commented out on purpose.
--   CREATE POLICY admin_all_cases   ON cases.fraud_cases  FOR ALL TO "alex.owen@databricks.com" USING (true) WITH CHECK (true);
--   CREATE POLICY admin_all_actions ON cases.case_actions FOR ALL TO "alex.owen@databricks.com" USING (true) WITH CHECK (true);

-- -----------------------------------------------------------------------------
-- Item 2: SET ROLE into every test role. NO CHANGE NEEDED.
-- pg_has_role(session_user, role, 'MEMBER') is true for fraud_pii, fraud_analyst,
-- fraud_lead and fraud_triage_agent, and SET ROLE / RESET ROLE succeed for all four.
-- These grants are already in lakebase_fgac.sql (GRANT ... TO CURRENT_USER).

-- -----------------------------------------------------------------------------
-- Item 7: tamper-resistant attribution (db_inserted_by)
-- -----------------------------------------------------------------------------
-- Step 1: add the column as nullable so existing rows are not stamped with the
-- session_user of whoever runs this DDL.
ALTER TABLE cases.fraud_cases  ADD COLUMN IF NOT EXISTS db_inserted_by TEXT;
ALTER TABLE cases.case_actions ADD COLUMN IF NOT EXISTS db_inserted_by TEXT;

-- Step 2: backfill with the best-known value.
-- Evidence (2026-10-21): the only human LOGIN role in fe_bar_db is
-- alex.owen@databricks.com. The other login roles (cloud_admin, databricks_*)
-- are Databricks system and sync roles that never write to cases.*. Every case
-- write so far went through LakebaseCases or validation notebooks connected as
-- alex.owen@databricks.com, with or without SET ROLE. With SET ROLE, session_user
-- is still the login, so that is the correct value.
UPDATE cases.fraud_cases  SET db_inserted_by = 'alex.owen@databricks.com' WHERE db_inserted_by IS NULL;
UPDATE cases.case_actions SET db_inserted_by = 'alex.owen@databricks.com' WHERE db_inserted_by IS NULL;

-- Step 3: enforce for new rows.
ALTER TABLE cases.fraud_cases  ALTER COLUMN db_inserted_by SET DEFAULT session_user;
ALTER TABLE cases.case_actions ALTER COLUMN db_inserted_by SET DEFAULT session_user;
ALTER TABLE cases.fraud_cases  ALTER COLUMN db_inserted_by SET NOT NULL;
ALTER TABLE cases.case_actions ALTER COLUMN db_inserted_by SET NOT NULL;

-- Step 4: the agent INSERT policies also require db_inserted_by = session_user,
-- so a caller cannot claim to be a different connecting identity.
-- created_by / actor stay as the analyst label supplied by the agent.
DROP POLICY IF EXISTS fraud_triage_agent_insert_cases ON cases.fraud_cases;
CREATE POLICY fraud_triage_agent_insert_cases
  ON cases.fraud_cases
  FOR INSERT
  TO fraud_triage_agent
  WITH CHECK (
    created_by LIKE 'fraud_triage_copilot%'
    AND db_inserted_by = session_user
  );

DROP POLICY IF EXISTS fraud_triage_agent_insert_actions ON cases.case_actions;
CREATE POLICY fraud_triage_agent_insert_actions
  ON cases.case_actions
  FOR INSERT
  TO fraud_triage_agent
  WITH CHECK (
    actor LIKE 'fraud_triage_copilot%'
    AND db_inserted_by = session_user
    AND EXISTS (SELECT 1 FROM cases.fraud_cases fc WHERE fc.case_id = case_actions.case_id)
  );
-- Analysts can only UPDATE (status, updated_at) via column grants, and the agent
-- has no UPDATE, so neither role can rewrite db_inserted_by after insert.

-- -----------------------------------------------------------------------------
-- Item 8: governed view over the calibration synced table
-- fraud.risk_score_calibration is a SNAPSHOT synced table from
-- workshop_guy_catalog.fe_bar_a0.risk_score_calibration (pipeline f8690359).
-- It holds no PII, so the view applies no row or column rule. It exists so that
-- governed roles read only through fraud_gov, the same pattern as the other views.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW fraud_gov.risk_score_calibration
  WITH (security_barrier = true)
AS
SELECT bucket, bucket_order, lower_bound, upper_bound, row_count, fraud_count,
       observed_precision, confidence, model_run_id, split_cutoff_ts, computed_at
FROM fraud.risk_score_calibration;

GRANT SELECT ON fraud_gov.risk_score_calibration TO fraud_analyst, fraud_lead, fraud_triage_agent;

-- -----------------------------------------------------------------------------
-- Item 9 (Step 9, 2026-11-04): Databricks App fe-bar-fraud-triage identity
-- The app's service principal (app-1xzuu6 fe-bar-fraud-triage, application ID
-- 8f239f44-078a-4f8f-90f1-4c1b0bcdc26c) logs in with a Postgres role of the same
-- name, created by the app's Lakebase resource (CAN_CONNECT_AND_CREATE).
-- Its ONLY privilege is membership in fraud_triage_agent, so it runs the agent's
-- code path via SET ROLE fraud_triage_agent. db_inserted_by (DEFAULT session_user)
-- records the app role, distinguishing app writes from human writes.
-- Not granted: BYPASSRLS, SUPERUSER, fraud_pii, fraud_lead, any direct grant on
-- fraud.* or cases.*. The app runs no DDL and creates no schemas.
-- Idempotent: skips if the role does not exist yet or membership already exists.
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '8f239f44-078a-4f8f-90f1-4c1b0bcdc26c')
     AND NOT pg_has_role('8f239f44-078a-4f8f-90f1-4c1b0bcdc26c', 'fraud_triage_agent', 'MEMBER') THEN
    GRANT fraud_triage_agent TO "8f239f44-078a-4f8f-90f1-4c1b0bcdc26c";
  END IF;
END $$;

-- =============================================================================
-- END
-- =============================================================================
