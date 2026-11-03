-- =============================================================================
-- Lakebase dashboard read layer: fraud_dash schema (Step 6, Layer 5)
-- Database: fe_bar_db (Lakebase project fe-bar-fraud-analytics, branch production)
-- Consumer: AI/BI dashboard "FE Bar Fraud Ops: Triage & Action" via the UC catalog
--           fe_bar_lakebase, which runs in Postgres as databricks_reader_<dbid>.
-- Idempotent: IF NOT EXISTS / CREATE OR REPLACE / re-runnable GRANTs.
-- Prerequisites: lakebase_cases_ddl.sql, lakebase_fgac.sql (roles, fraud_gov, RLS).
--
-- Governance design
-- * The UC path is not identity-aware: every dashboard viewer reaches Postgres as
--   databricks_reader_<dbid>. So fraud_dash only exposes data that is safe for a
--   NON-PII viewer: rows with amount > 10000 are excluded explicitly in every view,
--   and notes / created_by / db_inserted_by are never selected.
-- * Mechanism: views are OWNED BY fraud_lead. Postgres applies the RLS policies of
--   the view owner (security_invoker is off), so the existing
--   fraud_lead_select_cases / fraud_lead_select_actions policies (USING true) let
--   the view read cases, and the view's own WHERE clause narrows to non-high-amount
--   rows. No new RLS policy, and no change to existing policies. A policy for the
--   reader on cases.fraud_cases was rejected because it would also make the raw
--   table (incl. notes) readable through fe_bar_lakebase.cases.fraud_cases.
-- * The reader role gets USAGE on fraud_dash and SELECT on the fraud_dash objects
--   only. It is NOT given BYPASSRLS, superuser, fraud_pii / fraud_lead membership,
--   or any new grant on cases.* / fraud.*.
-- * security_barrier = true on every view so caller predicates cannot be pushed
--   below the view's filters (no leaky-function side channel).
-- * Thresholds are not hardcoded: fraud_dash.model_thresholds is loaded from the
--   MLflow run params (block_threshold, review_threshold) by
--   validation_notebooks/dashboard_validation.ipynb, and score_distribution reads
--   the latest row.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS fraud_dash;
COMMENT ON SCHEMA fraud_dash IS 'Dashboard read layer for the UC reader role: non-pii, aggregated where possible. See lakebase_dashboard.sql.';

-- fraud_lead owns the views, so it needs USAGE + CREATE on the schema.
GRANT USAGE, CREATE ON SCHEMA fraud_dash TO fraud_lead;

-- ---------------------------------------------------------------------------
-- Model thresholds (loaded from MLflow, never hardcoded)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fraud_dash.model_thresholds (
    model_run_id      TEXT PRIMARY KEY,
    block_threshold   DOUBLE PRECISION NOT NULL,
    review_threshold  DOUBLE PRECISION NOT NULL,
    loaded_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT ON fraud_dash.model_thresholds TO fraud_lead;

-- ---------------------------------------------------------------------------
-- Views, created as fraud_lead so fraud_lead owns them
-- ---------------------------------------------------------------------------
SET ROLE fraud_lead;

-- ---- fraud_dash.case_summary: one row per non-high-amount case -------------
CREATE OR REPLACE VIEW fraud_dash.case_summary
  WITH (security_barrier = true)
AS
SELECT
    c.case_id::text          AS case_id,
    c.txn_id,
    tf.customer_id,
    c.status,
    c.assigned_queue,
    c.recommended_action,
    c.created_at,
    c.updated_at,
    r.risk_score,
    tf.amount,
    COALESCE(a.action_count, 0) AS action_count,
    a.last_action_at
FROM cases.fraud_cases c
-- LATERAL lookups keep this an index probe per case (a plain join planned a
-- full scan of the 464K-row governed views).
JOIN LATERAL (
    SELECT f.customer_id, f.amount
    FROM fraud_gov.txn_features f
    WHERE f.txn_id = c.txn_id
    LIMIT 1
) tf ON tf.amount <= 10000                    -- high-amount cases excluded
LEFT JOIN LATERAL (
    SELECT x.risk_score
    FROM fraud_gov.txn_risk_current x
    WHERE x.txn_id = c.txn_id
    LIMIT 1
) r ON true
LEFT JOIN LATERAL (
    SELECT count(*) AS action_count, max(ca.created_at) AS last_action_at
    FROM cases.case_actions ca
    WHERE ca.case_id = c.case_id
) a ON true;
-- notes, created_by and db_inserted_by are deliberately not selected.

-- ---- fraud_dash.case_actions_daily ------------------------------------------
CREATE OR REPLACE VIEW fraud_dash.case_actions_daily
  WITH (security_barrier = true)
AS
SELECT
    (ca.created_at AT TIME ZONE 'UTC')::date AS action_date,
    ca.action_type,
    count(*)                                 AS action_count,
    count(DISTINCT ca.case_id)               AS case_count
FROM cases.case_actions ca
JOIN cases.fraud_cases c   ON c.case_id = ca.case_id
JOIN LATERAL (
    SELECT f.amount
    FROM fraud_gov.txn_features f
    WHERE f.txn_id = c.txn_id
    LIMIT 1
) tf ON tf.amount <= 10000
GROUP BY 1, 2;

-- ---- fraud_dash.score_distribution -------------------------------------------
-- 0.05-wide buckets below review_threshold; 0.01-wide buckets from
-- review_threshold up to block_threshold and from block_threshold up to 1.0,
-- so every bucket above review_threshold is pure in recommended_action.
CREATE OR REPLACE VIEW fraud_dash.score_distribution
  WITH (security_barrier = true)
AS
WITH t AS (
    SELECT block_threshold AS bt, review_threshold AS rt, model_run_id
    FROM fraud_dash.model_thresholds
    ORDER BY loaded_at DESC
    LIMIT 1
),
s AS (
    SELECT r.risk_score, r.recommended_action, t.bt, t.rt, t.model_run_id,
           CASE
             WHEN r.risk_score >= t.bt THEN t.bt + floor((r.risk_score - t.bt) / 0.01) * 0.01
             WHEN r.risk_score >= t.rt THEN t.rt + floor((r.risk_score - t.rt) / 0.01) * 0.01
             ELSE floor(r.risk_score / 0.05) * 0.05
           END AS lo,
           CASE
             WHEN r.risk_score >= t.bt THEN 'fine_block'
             WHEN r.risk_score >= t.rt THEN 'fine_review'
             ELSE 'coarse'
           END AS band
    FROM fraud_gov.txn_risk_current r
    JOIN fraud_gov.txn_features tf
      ON tf.txn_id = r.txn_id
     AND tf.amount <= 10000
    CROSS JOIN t
)
SELECT
    round(lo::numeric, 4)::double precision                         AS bucket_lower,
    round((CASE band
             WHEN 'fine_block'  THEN least(lo + 0.01, 1.0)
             WHEN 'fine_review' THEN least(lo + 0.01, bt)
             ELSE least(lo + 0.05, rt)
           END)::numeric, 4)::double precision                      AS bucket_upper,
    to_char(lo, 'FM0.000') ||
      CASE WHEN abs(lo - rt) < 1e-9 THEN ' | review threshold ' || to_char(rt, 'FM0.0000')
           WHEN abs(lo - bt) < 1e-9 THEN ' | block threshold '  || to_char(bt, 'FM0.0000')
           ELSE '' END                                               AS bucket_label,
    band,
    recommended_action,
    count(*)                                                         AS txn_count,
    rt                                                               AS review_threshold,
    bt                                                               AS block_threshold,
    model_run_id
FROM s
GROUP BY lo, band, recommended_action, rt, bt, model_run_id;

-- ---- fraud_dash.exposure -----------------------------------------------------
-- One row per (recommended_action, is_fraud). SUM over the view gives totals.
CREATE OR REPLACE VIEW fraud_dash.exposure
  WITH (security_barrier = true)
AS
SELECT
    r.recommended_action,
    tf.is_fraud,
    count(*)                                         AS txn_count,
    round(sum(tf.amount)::numeric, 2)::double precision AS total_amount,
    round(sum(CASE WHEN tf.is_fraud AND r.recommended_action IN ('block','review')
                   THEN tf.amount ELSE 0 END)::numeric, 2)::double precision AS fraud_amount_caught,
    round(sum(CASE WHEN tf.is_fraud AND r.recommended_action = 'approve'
                   THEN tf.amount ELSE 0 END)::numeric, 2)::double precision AS fraud_amount_missed
FROM fraud_gov.txn_risk_current r
JOIN fraud_gov.txn_features tf
  ON tf.txn_id = r.txn_id
 AND tf.amount <= 10000
GROUP BY 1, 2;

-- ---- fraud_dash.baseline_comparison ------------------------------------------
-- Model (block + review bands) vs a static rule, on the same rows.
CREATE OR REPLACE VIEW fraud_dash.baseline_comparison
  WITH (security_barrier = true)
AS
WITH base AS (
    SELECT tf.amount, tf.is_fraud,
           (r.recommended_action IN ('block','review'))          AS model_flag,
           (tf.is_cross_border = 1 AND tf.is_new_device = 1)     AS rule_flag
    FROM fraud_gov.txn_risk_current r
    JOIN fraud_gov.txn_features tf
      ON tf.txn_id = r.txn_id
     AND tf.amount <= 10000
),
m AS (
    SELECT 'model'::text AS strategy,
           'recommended_action IN (block, review)'::text AS rule_text,
           model_flag AS flagged, amount, is_fraud FROM base
    UNION ALL
    SELECT 'baseline_rule',
           'is_cross_border = 1 AND is_new_device = 1',
           rule_flag, amount, is_fraud FROM base
)
SELECT
    strategy,
    rule_text,
    count(*)                                              AS rows_evaluated,
    count(*) FILTER (WHERE flagged)                       AS flagged_count,
    count(*) FILTER (WHERE flagged AND is_fraud)          AS fraud_caught_count,
    round(coalesce(sum(amount) FILTER (WHERE flagged AND is_fraud), 0)::numeric, 2)::double precision AS fraud_amount_caught,
    count(*) FILTER (WHERE flagged AND NOT is_fraud)      AS false_positive_count,
    count(*) FILTER (WHERE NOT flagged AND is_fraud)      AS fraud_missed_count,
    round(coalesce(sum(amount) FILTER (WHERE NOT flagged AND is_fraud), 0)::numeric, 2)::double precision AS fraud_amount_missed,
    round(coalesce(sum(amount) FILTER (WHERE is_fraud), 0)::numeric, 2)::double precision AS total_fraud_amount
FROM m
GROUP BY 1, 2;

-- ---- fraud_dash.triage_queue -------------------------------------------------
-- Flagged (block / review), non-high-amount transactions with their latest case.
-- Backs the Triage queue table; ranked in Postgres so the dashboard pulls 50 rows.
CREATE OR REPLACE VIEW fraud_dash.triage_queue
  WITH (security_barrier = true)
AS
SELECT
    r.txn_id,
    r.customer_id,
    tf.amount,
    r.risk_score,
    r.recommended_action,
    -- Step 8 (2026-11-03): blank the SHAP feature value for amt_to_monthly_spend.
    -- amount / that value would reveal the masked dim_customer_silver.avg_monthly_spend.
    regexp_replace(r.top_shap_signals,
                   '("feature": "amt_to_monthly_spend", "value": )[^,}]+',
                   '\1null', 'g')        AS top_shap_signals,
    COALESCE(c.status, 'no case')         AS case_status,
    COALESCE(c.assigned_queue, 'no case') AS assigned_queue,
    c.case_id::text                       AS case_id,
    row_number() OVER (ORDER BY r.risk_score DESC, r.txn_id) AS risk_rank
FROM fraud_gov.txn_risk_current r
JOIN fraud_gov.txn_features tf
  ON tf.txn_id = r.txn_id
 AND tf.amount <= 10000
LEFT JOIN LATERAL (
    SELECT fc.case_id, fc.status, fc.assigned_queue
    FROM cases.fraud_cases fc
    WHERE fc.txn_id = r.txn_id
    ORDER BY (fc.status <> 'closed') DESC, fc.created_at DESC
    LIMIT 1
) c ON true
WHERE r.recommended_action IN ('block', 'review');

RESET ROLE;

-- ---------------------------------------------------------------------------
-- Grants to the UC reader role ONLY (databricks_reader_<oid of this database>)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    reader text := 'databricks_reader_' || (SELECT oid FROM pg_database WHERE datname = current_database());
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = reader) THEN
        RAISE EXCEPTION 'UC reader role % not found; register the database as a UC catalog first', reader;
    END IF;
    EXECUTE format('GRANT USAGE ON SCHEMA fraud_dash TO %I', reader);
    EXECUTE format('GRANT SELECT ON fraud_dash.case_summary        TO %I', reader);
    EXECUTE format('GRANT SELECT ON fraud_dash.case_actions_daily  TO %I', reader);
    EXECUTE format('GRANT SELECT ON fraud_dash.score_distribution  TO %I', reader);
    EXECUTE format('GRANT SELECT ON fraud_dash.exposure            TO %I', reader);
    EXECUTE format('GRANT SELECT ON fraud_dash.baseline_comparison TO %I', reader);
    EXECUTE format('GRANT SELECT ON fraud_dash.triage_queue        TO %I', reader);
    EXECUTE format('GRANT SELECT ON fraud_dash.model_thresholds    TO %I', reader);
END $$;

-- ============================================================
-- END
-- ============================================================
