# Architecture (full)

Moved from README.md in Step 10. The old "five layers" overview is rewritten here as the six required stages. The compact diagram is in `README.md`. 100% synthetic data.

## Six stages

The build serves two personas: the **Head of Fraud Risk Ops**, who watches exposure, model performance and case volume, and the **Fraud Analyst**, who works a triage queue and opens cases.

1. **Lakeflow (ingest).** Synthetic card data (customers, merchants, transactions, prior fraud cases, with a seeded high-risk cohort) lands as JSON in a UC volume. Spark Declarative Pipeline c0db28b8 turns it into bronze (Auto Loader streaming tables), silver (materialized views with expectations and dedup) and gold features.
2. **Unity Catalog (govern).** Row filter `filter_high_amount_txns` on silver and gold, masks on `avg_monthly_spend` and `avg_amount_30d`, least-privilege grants for `account users`, and direct grants for the App service principal (`uc_app_grants.sql`).
3. **Lakebase (operational serving).** Gold features and scores sync to Lakebase Postgres as SNAPSHOT synced tables. Native OLTP case tables sit alongside them, with Postgres FGAC.
4. **ML and Gen AI (make it intelligent).** A LightGBM model in UC scores every transaction with the top 3 SHAP signals. A tool-calling agent (Fraud Triage Copilot) explains a flagged transaction and opens a case in Lakebase under its own governed Postgres role.
5. **Genie Agent (natural language).** Genie space FE Bar Fraud Risk Ops answers questions over the six `fraud_dash` views and `risk_score_calibration` only.
6. **Databricks App (surface it to the business).** Streamlit app `fe-bar-fraud-triage`: triage queue, transaction detail with Explain / Open case through the in-process agent, Ask Genie, and a link to the AI/BI dashboard, which reads live from Lakebase.

Step numbers in the prompts differ from stage numbers: Steps 1 and 2 built stage 1, Step 3 the Lakebase stage, Step 4 the model, Step 5 the agent and Postgres FGAC, Step 6 the dashboard, Step 8 the Genie Agent and the UC hardening, Step 9 the App.

## Diagram (data path, Steps 1 to 6)

```
 Synthetic generator (card_transaction_bronze_generator.ipynb)
   | JSON, ~15% DQ errors
   v
 /Volumes/workshop_guy_catalog/fe_bar_a0/staging/{customers,merchants,transactions,prior_fraud_cases}/
   | Auto Loader (read_files)
   v
 SDP pipeline c0db28b8  ("FE BAR Bronze Silver AutoLoader Pipeline.sql" + gold_feature_layer.sql)
   bronze STs: dim_customer_bronze, dim_merchant_bronze, fact_transactions_bronze, fact_prior_fraud_cases_bronze
   silver MVs: dim_customer_silver [MASK avg_monthly_spend], dim_merchant_silver,
               fact_transactions_silver [ROW FILTER amount > 10000], fact_prior_fraud_cases_silver
   gold MVs:   txn_features_gold, customer_risk_profile_gold
   |                                   |
   | fraud_model_training -> UC model  | SNAPSHOT synced tables (sync pipeline f8690359)
   | fraud_risk_model@champion v1      v
   v                                  Lakebase project fe-bar-fraud-analytics / branch production / db fe_bar_db
 fraud_batch_scoring                   (UC catalog fe_bar_lakebase)
   -> scored_transactions  ---sync--->  fraud.txn_features, fraud.customer_risk_profile,
   -> risk_score_calibration --sync-->  fraud.txn_risk_current, fraud.risk_score_calibration   (read-only copies)
                                         |
                                         v  security_barrier views, pg_has_role(fraud_pii)
                                        fraud_gov.*  (row rule amount > 10000, column rule amt_to_monthly_spend)
                                         |                         |
   Fraud Triage Copilot (fraud_triage_agent.py)                    |
   SET ROLE fraud_triage_agent: reads fraud_gov.*,                 |
   writes cases.fraud_cases / cases.case_actions (FORCE RLS) ------+
                                         |                         |
                                         v                         v
                                        fraud_dash.* views (owned by fraud_lead, non-pii safe)
                                         | UC reader role databricks_reader_17063
                                         v
                     AI/BI dashboard "FE Bar Fraud Ops: Triage & Action" (warehouse 9bbc027402111984)

 Job fe_bar_gold_to_lakebase (1115396029932218): gold_pipeline_refresh -> batch_scoring -> lakebase_sync_refresh
```

Steps 8 and 9 add, on top of this diagram: since 2026-11-04, the row filter also sits on `txn_features_gold` and the mask on `customer_risk_profile_gold.avg_amount_30d`. The Genie space reads `fraud_dash.*` and `risk_score_calibration` through UC. The App runs the agent in-process as its service principal, which logs in to Postgres as its own role (member of `fraud_triage_agent`), and calls the Genie space.
