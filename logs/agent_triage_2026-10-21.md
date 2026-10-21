# Agent Triage Log — 2026-10-21

## FM Endpoint
**databricks-claude-sonnet-5-5** (system.ai.databricks-claude-sonnet-5-5)
Chosen because it is the highest-numbered Claude Sonnet endpoint available, with strong tool-calling support.
Note: does not support the `temperature` parameter.

## UC Function Signatures
| Function | Returns | Source Tables |
|----------|---------|---------------|
| get_transaction_risk(txn_id STRING) | TABLE(txn_id, customer_id, txn_ts, amount, risk_score, recommended_action, model_version, scored_at, confidence, routed_queue) | fe_bar_lakebase.fraud.txn_risk_current, .txn_features |
| explain_top_signals(txn_id STRING) | TABLE(txn_id, signal_name, shap_value, feature_value, customer_normal, explanation) | fe_bar_lakebase.fraud.txn_risk_current, .txn_features, .customer_risk_profile |
| get_customer_history(customer_id STRING) | TABLE(section, detail) | fe_bar_lakebase.fraud.customer_risk_profile, .txn_risk_current, .txn_features; workshop_guy_catalog.fe_bar_a0.fact_prior_fraud_cases_silver; fe_bar_lakebase.cases.fraud_cases |
| create_fraud_case(txn_id, action, notes) | JSON string {case_id, status} | Agent-side Python tool wrapping LakebaseCases(pg_role='fraud_triage_agent') |

## E.1 Explain — TXN-0234209
Trace ID: tr-d189164333a825572d0670df21c319ea
Latency: 44.1s

Key output: Risk score 0.984, recommended block, confidence HIGH, queue auto_block.
Top signals: new device (SHAP +2.57), 450.6 km from home (SHAP +1.87), online (SHAP +1.20).
Customer CUST-08669: 3 prior confirmed fraud, 0 not-fraud. Low risk segment, 40mo tenure.

## E.2 Act — TXN-0234209
Trace ID: tr-2fb3e5d6190f61225d050ad0d35e23d8
Latency: 43.4s
Case ID: 2319d4b7-bea3-412b-ba6b-8325e1a7a71d
Action: block, Queue: auto_block, created_by: fraud_triage_copilot:agent

## E.5 Batch Triage — Top 5 Block
| txn_id | risk_score | case_id |
|--------|-----------|--------|
| TXN-0147293 | 0.993762 | 82b12d25-bf88-47cb-b0a4-f5a5b62f349d |
| TXN-0288343 | 0.992881 | 863334d8-909e-4348-8be4-772d0c7f6e72 |
| TXN-0221786 | 0.992875 | c37587c0-5091-4fd7-a656-c9df9417d0e3 |
| TXN-0417769 | 0.992698 | 98edced4-9dc7-47a3-bbf3-1694bb7b1b43 |
| TXN-0432087 | 0.992657 | 98adcae4-cec6-46a1-a2c5-1ecd84c299ad |

## E.6 Guardrails
- TXN-9999999 (unknown): Agent returned clear not-found message, no case created.
- TXN-0278800 (approve band, score 0.8714): Agent refused to block, explained it's approve-band. Did not create case.

## Model Registration
- Registered: workshop_guy_catalog.fe_bar_a0.fraud_triage_agent v1 @champion
- Experiment: /Users/alex.owen@databricks.com/fe_bar_fraud_triage_agent
- Resources: DatabricksServingEndpoint(databricks-claude-sonnet-5-5), 3 DatabricksFunction UC functions

## Deployment Notes
A later Databricks App deployment would need:
1. app.yaml: Add serving_endpoint resource for databricks-claude-sonnet-5-5
2. Lakebase auth: The app's service principal needs a Postgres role (fraud_triage_agent member) created in Lakebase. The SP uses generate_database_credential to get OAuth tokens. Deploy the app first so the SP creates/owns schemas.
3. The app needs psycopg[binary] and the lakebase_cases.py module.
