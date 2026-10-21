-- =============================================================================
-- Agent Tools: UC SQL Functions for Fraud Triage Copilot
-- Schema: workshop_guy_catalog.fe_bar_a0
-- Reads from: fe_bar_lakebase.fraud.* (synced tables, direct — NOT fraud_gov)
-- Reason: fraud_gov views use pg_has_role() which always returns FALSE through
--         UC because UC queries run as a Postgres system role, not the user's
--         personal role.  The synced tables have no Postgres-level FGAC so they
--         return the full dataset through UC.  UC-level FGAC (row filter on
--         silver) does NOT propagate to Lakebase synced tables.
-- =============================================================================

-- NOTE: create_fraud_case is implemented as an agent-side Python tool wrapping
-- LakebaseCases(pg_role='fraud_triage_agent') because UC functions cannot
-- obtain Lakebase OAuth credentials or connect to Postgres directly.
-- See fraud_triage_agent.py for the implementation.

-- C.1  get_transaction_risk
-- Thresholds from MLflow run d89beaca8f81447780da60ed2ea7c811:
--   block_threshold  = 0.950267
--   review_threshold = 0.871416
-- Confidence rule:  HIGH when score >= threshold + 0.03 for its band (or
--   score < threshold - 0.03 for approve); MEDIUM otherwise.

CREATE OR REPLACE FUNCTION workshop_guy_catalog.fe_bar_a0.get_transaction_risk(
  txn_id STRING COMMENT 'The transaction ID to look up, e.g. TXN-0234209'
)
RETURNS TABLE (
  txn_id STRING, customer_id STRING, txn_ts TIMESTAMP, amount DOUBLE,
  risk_score DOUBLE, recommended_action STRING, model_version STRING,
  scored_at TIMESTAMP, confidence STRING, routed_queue STRING
)
COMMENT 'Returns the risk assessment for a single transaction including risk score, recommended action, confidence (high/medium), and routed queue (auto_block/analyst_review/auto_approve).'
RETURN
  SELECT sr.txn_id, sr.customer_id, tf.txn_ts, tf.amount, sr.risk_score,
         sr.recommended_action, sr.model_version, sr.scored_at,
         CASE
           WHEN sr.recommended_action='block'   AND sr.risk_score >= 0.980267 THEN 'high'
           WHEN sr.recommended_action='review'  AND sr.risk_score >= 0.901416 AND sr.risk_score < 0.950267 THEN 'high'
           WHEN sr.recommended_action='approve' AND sr.risk_score <  0.841416 THEN 'high'
           ELSE 'medium'
         END AS confidence,
         CASE sr.recommended_action
           WHEN 'block' THEN 'auto_block'
           WHEN 'review' THEN 'analyst_review'
           WHEN 'approve' THEN 'auto_approve'
         END AS routed_queue
  FROM fe_bar_lakebase.fraud.txn_risk_current sr
  JOIN fe_bar_lakebase.fraud.txn_features tf ON sr.txn_id = tf.txn_id
  WHERE sr.txn_id = get_transaction_risk.txn_id;

-- C.2  explain_top_signals
-- JSON format: [{"feature": "...", "value": N, "shap": N}, ...]

CREATE OR REPLACE FUNCTION workshop_guy_catalog.fe_bar_a0.explain_top_signals(
  txn_id STRING COMMENT 'The transaction ID whose top SHAP signals to explain'
)
RETURNS TABLE (
  txn_id STRING, signal_name STRING, shap_value DOUBLE,
  feature_value STRING, customer_normal STRING, explanation STRING
)
COMMENT 'Returns the top SHAP signals for a scored transaction as plain-language explanations with SHAP values and customer context.'
RETURN
  WITH parsed AS (
    SELECT sr.txn_id, sr.customer_id,
           explode(from_json(sr.top_shap_signals,
             'ARRAY<STRUCT<feature: STRING, value: DOUBLE, shap: DOUBLE>>')) AS sig
    FROM fe_bar_lakebase.fraud.txn_risk_current sr
    WHERE sr.txn_id = explain_top_signals.txn_id
  ),
  features AS (SELECT * FROM fe_bar_lakebase.fraud.txn_features WHERE txn_id = explain_top_signals.txn_id),
  customer AS (SELECT * FROM fe_bar_lakebase.fraud.customer_risk_profile WHERE customer_id = (SELECT customer_id FROM features LIMIT 1))
  SELECT p.txn_id, p.sig.feature AS signal_name, p.sig.shap AS shap_value,
    CASE p.sig.feature
      WHEN 'is_new_device' THEN CAST(CAST(p.sig.value AS INT) AS STRING)
      WHEN 'geo_distance_from_home' THEN CAST(ROUND(p.sig.value,1) AS STRING)||' km'
      WHEN 'is_online' THEN CAST(CAST(p.sig.value AS INT) AS STRING)
      WHEN 'amount' THEN '$'||CAST(ROUND(p.sig.value,2) AS STRING)
      ELSE CAST(ROUND(p.sig.value,4) AS STRING)
    END AS feature_value,
    CASE p.sig.feature
      WHEN 'is_new_device' THEN 'Customer uses '||CAST(c.distinct_devices_30d AS STRING)||' devices in 30d'
      WHEN 'geo_distance_from_home' THEN 'Home region: '||c.home_region
      WHEN 'is_online' THEN 'Customer avg 30d txns: '||CAST(c.txn_count_30d AS STRING)
      WHEN 'amount' THEN 'Avg 30d: $'||CAST(ROUND(c.avg_amount_30d,2) AS STRING)
      ELSE 'See customer profile'
    END AS customer_normal,
    CASE p.sig.feature
      WHEN 'is_new_device' THEN CASE WHEN p.sig.value=1 THEN 'New device (SHAP +'||CAST(ROUND(p.sig.shap,2) AS STRING)||'). Normally uses '||CAST(c.distinct_devices_30d AS STRING)||' devices.' ELSE 'Known device.' END
      WHEN 'geo_distance_from_home' THEN CAST(ROUND(p.sig.value,1) AS STRING)||' km from home ('||c.home_region||'), SHAP +'||CAST(ROUND(p.sig.shap,2) AS STRING)||'.'
      WHEN 'is_online' THEN CASE WHEN p.sig.value=1 THEN 'Online txn (SHAP +'||CAST(ROUND(p.sig.shap,2) AS STRING)||'). Higher risk.' ELSE 'In-person.' END
      WHEN 'amount' THEN '$'||CAST(ROUND(p.sig.value,2) AS STRING)||' vs avg $'||CAST(ROUND(c.avg_amount_30d,2) AS STRING)||' (SHAP +'||CAST(ROUND(p.sig.shap,2) AS STRING)||').'
      ELSE p.sig.feature||' = '||CAST(ROUND(p.sig.value,4) AS STRING)||' (SHAP +'||CAST(ROUND(p.sig.shap,2) AS STRING)||')'
    END AS explanation
  FROM parsed p LEFT JOIN features f ON p.txn_id = f.txn_id LEFT JOIN customer c ON true
  ORDER BY p.sig.shap DESC;

-- C.3  get_customer_history

CREATE OR REPLACE FUNCTION workshop_guy_catalog.fe_bar_a0.get_customer_history(
  customer_id STRING COMMENT 'The customer ID to look up, e.g. CUST-08669'
)
RETURNS TABLE (section STRING, detail STRING)
COMMENT 'Returns customer risk profile, last 20 transactions with risk scores, prior fraud outcome counts, and existing fraud cases.'
RETURN
  WITH profile AS (
    SELECT 'profile' AS section, 'customer_id='||crp.customer_id||' | tenure='||CAST(crp.tenure AS STRING)||' | home_region='||crp.home_region||' | risk_segment='||crp.risk_segment||' | txn_count_30d='||CAST(crp.txn_count_30d AS STRING)||' | avg_amount_30d=$'||CAST(ROUND(crp.avg_amount_30d,2) AS STRING)||' | distinct_devices_30d='||CAST(crp.distinct_devices_30d AS STRING)||' | prior_case_count='||CAST(crp.prior_case_count AS STRING)||' | confirmed_fraud_count='||CAST(crp.confirmed_fraud_count AS STRING) AS detail
    FROM fe_bar_lakebase.fraud.customer_risk_profile crp WHERE crp.customer_id = get_customer_history.customer_id
  ),
  recent_txns AS (
    SELECT 'recent_txns' AS section, 'txn_id='||tr.txn_id||' | amount=$'||CAST(ROUND(tf.amount,2) AS STRING)||' | risk_score='||CAST(ROUND(tr.risk_score,4) AS STRING)||' | action='||tr.recommended_action||' | txn_ts='||CAST(tf.txn_ts AS STRING) AS detail
    FROM fe_bar_lakebase.fraud.txn_risk_current tr JOIN fe_bar_lakebase.fraud.txn_features tf ON tr.txn_id = tf.txn_id
    WHERE tf.customer_id = get_customer_history.customer_id ORDER BY tf.txn_ts DESC LIMIT 20
  ),
  prior_outcomes AS (
    SELECT 'prior_outcomes' AS section, 'confirmed_fraud='||CAST(SUM(CASE WHEN pf.investigation_outcome='confirmed_fraud' THEN 1 ELSE 0 END) AS STRING)||' | not_fraud='||CAST(SUM(CASE WHEN pf.investigation_outcome='not_fraud' THEN 1 ELSE 0 END) AS STRING)||' | total='||CAST(COUNT(*) AS STRING) AS detail
    FROM workshop_guy_catalog.fe_bar_a0.fact_prior_fraud_cases_silver pf WHERE pf.customer_id = get_customer_history.customer_id
  ),
  existing_cases AS (
    SELECT 'existing_cases' AS section, 'case_id='||CAST(fc.case_id AS STRING)||' | txn_id='||fc.txn_id||' | status='||fc.status||' | queue='||fc.assigned_queue AS detail
    FROM fe_bar_lakebase.cases.fraud_cases fc JOIN fe_bar_lakebase.fraud.txn_features tf ON fc.txn_id = tf.txn_id
    WHERE tf.customer_id = get_customer_history.customer_id
  )
  SELECT * FROM profile UNION ALL SELECT * FROM recent_txns UNION ALL SELECT * FROM prior_outcomes UNION ALL SELECT * FROM existing_cases;
