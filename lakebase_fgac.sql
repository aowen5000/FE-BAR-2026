-- =============================================================================
-- Lakebase FGAC: Fine-Grained Access Control for fe_bar_db
-- Database: fe_bar_db (Lakebase project fe-bar-fraud-analytics)
-- Idempotent: all statements use IF NOT EXISTS / OR REPLACE / DO NOTHING
-- Updated 2026-10-21 (FGAC hardening): db_inserted_by = session_user in the agent
-- INSERT policies (Item 7), plus the fraud_gov.risk_score_calibration view (Item 8).
-- Prerequisites: lakebase_cases_ddl.sql (cases.* incl. db_inserted_by) and the
-- synced table fraud.risk_score_calibration.
-- Admin note (Item 1): the admin login (alex.owen@databricks.com) has BYPASSRLS,
-- so FORCE RLS does not lock it out and no admin policy is needed. For an admin
-- without BYPASSRLS, add: CREATE POLICY admin_all_* ... FOR ALL TO <admin> USING (true) WITH CHECK (true).
-- =============================================================================

-- ============================================================
-- B.1  ROLES
-- ============================================================

-- fraud_pii: mirrors the UC 'pii' group.  Members see all rows and
-- the real avg_monthly_spend / amt_to_monthly_spend columns.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'fraud_pii') THEN
    CREATE ROLE fraud_pii NOLOGIN;
  END IF;
END $$;

-- fraud_analyst: non-pii analyst persona.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'fraud_analyst') THEN
    CREATE ROLE fraud_analyst NOLOGIN;
  END IF;
END $$;

-- fraud_lead: pii persona (Head of Fraud Ops).  Member of fraud_pii.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'fraud_lead') THEN
    CREATE ROLE fraud_lead NOLOGIN;
  END IF;
END $$;
GRANT fraud_pii TO fraud_lead;

-- fraud_triage_agent: the agent's role.  Member of fraud_pii because it
-- acts on behalf of pii-authorized analysts.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'fraud_triage_agent') THEN
    CREATE ROLE fraud_triage_agent NOLOGIN;
  END IF;
END $$;
GRANT fraud_pii TO fraud_triage_agent;

-- Grant the current (superuser) role membership in fraud_pii for testing.
-- NOTE: membership is managed manually in Postgres for this build.
GRANT fraud_pii     TO CURRENT_USER;
GRANT fraud_analyst TO CURRENT_USER;
GRANT fraud_lead    TO CURRENT_USER;
GRANT fraud_triage_agent TO CURRENT_USER;

-- ============================================================
-- B.2  GOVERNED READ LAYER  (fraud_gov schema)
-- ============================================================

CREATE SCHEMA IF NOT EXISTS fraud_gov;

-- Grant USAGE on schemas needed by the governed roles.
GRANT USAGE ON SCHEMA fraud_gov TO fraud_analyst, fraud_lead, fraud_triage_agent;
GRANT USAGE ON SCHEMA fraud     TO fraud_analyst, fraud_lead, fraud_triage_agent;
GRANT USAGE ON SCHEMA cases     TO fraud_analyst, fraud_lead, fraud_triage_agent;

-- ---- fraud_gov.txn_risk_current ----
CREATE OR REPLACE VIEW fraud_gov.txn_risk_current
  WITH (security_barrier = true)
AS
SELECT
    txn_id,
    customer_id,
    risk_score,
    recommended_action,
    top_shap_signals,
    model_version,
    scored_at
FROM fraud.txn_risk_current
WHERE
    -- Row rule: high-amount txns only visible to fraud_pii members.
    -- We need the amount from txn_features to apply the rule.
    EXISTS (
        SELECT 1 FROM fraud.txn_features tf
        WHERE tf.txn_id = fraud.txn_risk_current.txn_id
          AND (tf.amount <= 10000 OR pg_has_role(current_user, 'fraud_pii', 'MEMBER'))
    );

-- ---- fraud_gov.txn_features ----
CREATE OR REPLACE VIEW fraud_gov.txn_features
  WITH (security_barrier = true)
AS
SELECT
    txn_id,
    customer_id,
    merchant_id,
    txn_ts,
    amount,
    -- Column rule: amt_to_monthly_spend is derived from avg_monthly_spend.
    -- NULL unless the caller is a fraud_pii member.
    CASE WHEN pg_has_role(current_user, 'fraud_pii', 'MEMBER')
         THEN amt_to_monthly_spend
         ELSE NULL
    END AS amt_to_monthly_spend,
    home_country,
    is_cross_border,
    geo_distance_from_home,
    is_new_device,
    device_id,
    is_online,
    channel,
    risk_tier,
    risk_segment,
    merchant_country,
    txn_count_1h,
    txn_count_24h,
    amt_to_cust_avg_30d,
    secs_since_prev_txn,
    hour_of_day,
    is_night,
    mcc_category,
    tenure,
    is_fraud
FROM fraud.txn_features
WHERE
    -- Row rule: rows with amount > 10000 are only returned for fraud_pii members.
    amount <= 10000 OR pg_has_role(current_user, 'fraud_pii', 'MEMBER');

-- ---- fraud_gov.customer_risk_profile ----
CREATE OR REPLACE VIEW fraud_gov.customer_risk_profile
  WITH (security_barrier = true)
AS
SELECT
    customer_id,
    tenure,
    home_region,
    risk_segment,
    txn_count_30d,
    avg_amount_30d,
    distinct_devices_30d,
    distinct_countries_30d,
    cross_border_txns_30d,
    last_txn_ts,
    prior_case_count,
    confirmed_fraud_count
FROM fraud.customer_risk_profile;
-- No row or column restrictions on customer_risk_profile.
-- The UC mask is on avg_monthly_spend (dim_customer_silver), which is not
-- a column in customer_risk_profile_gold.

-- Grant SELECT on fraud_gov views to the governed roles.
-- Do NOT grant direct SELECT on fraud.* synced tables.
GRANT SELECT ON fraud_gov.txn_risk_current      TO fraud_analyst, fraud_lead, fraud_triage_agent;
GRANT SELECT ON fraud_gov.txn_features           TO fraud_analyst, fraud_lead, fraud_triage_agent;
GRANT SELECT ON fraud_gov.customer_risk_profile  TO fraud_analyst, fraud_lead, fraud_triage_agent;

-- ---- fraud_gov.risk_score_calibration (Item 8) ----
-- Calibration buckets (no PII), synced SNAPSHOT from
-- workshop_guy_catalog.fe_bar_a0.risk_score_calibration via pipeline f8690359.
CREATE OR REPLACE VIEW fraud_gov.risk_score_calibration
  WITH (security_barrier = true)
AS
SELECT bucket, bucket_order, lower_bound, upper_bound, row_count, fraud_count,
       observed_precision, confidence, model_run_id, split_cutoff_ts, computed_at
FROM fraud.risk_score_calibration;
GRANT SELECT ON fraud_gov.risk_score_calibration TO fraud_analyst, fraud_lead, fraud_triage_agent;

-- ============================================================
-- B.3  RLS ON NATIVE CASE TABLES
-- ============================================================

-- Enable and force RLS on fraud_cases and case_actions.
-- FORCE means the table owner also gets filtered (we use SET ROLE to test).
ALTER TABLE cases.fraud_cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE cases.fraud_cases FORCE ROW LEVEL SECURITY;
ALTER TABLE cases.case_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE cases.case_actions FORCE ROW LEVEL SECURITY;

-- Drop existing policies (idempotent)
DO $$ BEGIN
  -- fraud_cases policies
  DROP POLICY IF EXISTS fraud_lead_select_cases ON cases.fraud_cases;
  DROP POLICY IF EXISTS fraud_analyst_select_cases ON cases.fraud_cases;
  DROP POLICY IF EXISTS fraud_analyst_update_cases ON cases.fraud_cases;
  DROP POLICY IF EXISTS fraud_triage_agent_select_cases ON cases.fraud_cases;
  DROP POLICY IF EXISTS fraud_triage_agent_insert_cases ON cases.fraud_cases;
  -- case_actions policies
  DROP POLICY IF EXISTS fraud_lead_select_actions ON cases.case_actions;
  DROP POLICY IF EXISTS fraud_analyst_select_actions ON cases.case_actions;
  DROP POLICY IF EXISTS fraud_triage_agent_select_actions ON cases.case_actions;
  DROP POLICY IF EXISTS fraud_triage_agent_insert_actions ON cases.case_actions;
END $$;

-- ---- fraud_lead: full visibility on all cases and actions ----
CREATE POLICY fraud_lead_select_cases
  ON cases.fraud_cases
  FOR SELECT
  TO fraud_lead
  USING (true);

CREATE POLICY fraud_lead_select_actions
  ON cases.case_actions
  FOR SELECT
  TO fraud_lead
  USING (true);

-- ---- fraud_analyst: limited visibility ----
-- Can see cases only if assigned_queue = 'analyst_review' AND the txn is
-- not high-amount (amount <= 10000 via fraud_gov.txn_features).
CREATE POLICY fraud_analyst_select_cases
  ON cases.fraud_cases
  FOR SELECT
  TO fraud_analyst
  USING (
    assigned_queue = 'analyst_review'
    AND EXISTS (
      SELECT 1 FROM fraud_gov.txn_features tf
      WHERE tf.txn_id = fraud_cases.txn_id
        AND tf.amount <= 10000
    )
  );

-- Analyst can UPDATE only status and updated_at on visible rows.
CREATE POLICY fraud_analyst_update_cases
  ON cases.fraud_cases
  FOR UPDATE
  TO fraud_analyst
  USING (
    assigned_queue = 'analyst_review'
    AND EXISTS (
      SELECT 1 FROM fraud_gov.txn_features tf
      WHERE tf.txn_id = fraud_cases.txn_id
        AND tf.amount <= 10000
    )
  );

-- Column-level GRANT: analyst can only UPDATE status and updated_at.
GRANT UPDATE (status, updated_at) ON cases.fraud_cases TO fraud_analyst;

-- case_actions visibility follows the parent case.
CREATE POLICY fraud_analyst_select_actions
  ON cases.case_actions
  FOR SELECT
  TO fraud_analyst
  USING (
    EXISTS (
      SELECT 1 FROM cases.fraud_cases fc
      WHERE fc.case_id = case_actions.case_id
        AND fc.assigned_queue = 'analyst_review'
        AND EXISTS (
          SELECT 1 FROM fraud_gov.txn_features tf
          WHERE tf.txn_id = fc.txn_id
            AND tf.amount <= 10000
        )
    )
  );

-- ---- fraud_triage_agent: full read, governed write ----
-- Can SELECT all cases (needed for the idempotency check).
CREATE POLICY fraud_triage_agent_select_cases
  ON cases.fraud_cases
  FOR SELECT
  TO fraud_triage_agent
  USING (true);

-- Can INSERT into fraud_cases only if created_by matches the agent prefix AND
-- db_inserted_by is the real connecting login (tamper-resistant attribution).
CREATE POLICY fraud_triage_agent_insert_cases
  ON cases.fraud_cases
  FOR INSERT
  TO fraud_triage_agent
  WITH CHECK (
    created_by LIKE 'fraud_triage_copilot%'
    AND db_inserted_by = session_user
  );

-- Can SELECT all case_actions.
CREATE POLICY fraud_triage_agent_select_actions
  ON cases.case_actions
  FOR SELECT
  TO fraud_triage_agent
  USING (true);

-- Can INSERT case_actions only for cases it can see, and actor must match.
CREATE POLICY fraud_triage_agent_insert_actions
  ON cases.case_actions
  FOR INSERT
  TO fraud_triage_agent
  WITH CHECK (
    actor LIKE 'fraud_triage_copilot%'
    AND db_inserted_by = session_user
    AND EXISTS (
      SELECT 1 FROM cases.fraud_cases fc
      WHERE fc.case_id = case_actions.case_id
    )
  );

-- Grant INSERT on fraud_cases and case_actions to the agent.
GRANT INSERT ON cases.fraud_cases  TO fraud_triage_agent;
GRANT INSERT ON cases.case_actions TO fraud_triage_agent;

-- Grant SELECT on fraud_cases and case_actions to all three roles.
GRANT SELECT ON cases.fraud_cases  TO fraud_analyst, fraud_lead, fraud_triage_agent;
GRANT SELECT ON cases.case_actions TO fraud_analyst, fraud_lead, fraud_triage_agent;

-- Grant USAGE on sequences needed for UUID generation (gen_random_uuid uses
-- pg_crypto, not sequences, so no sequence grants are needed).
-- No sequences to grant; UUIDs use gen_random_uuid().

-- ============================================================
-- END
-- ============================================================
