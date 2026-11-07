# Decisions and trade-offs

My decisions, condensed. Each one names its evidence file. 100% synthetic data.

## Data and pipeline

* **Synthetic scale and seeded cohort.** I chose 10K customers, 5K merchants, 500K transactions and 50K prior cases (seed 42) over a larger set. It is big enough for a time split and a rare label, and small enough for fast serverless runs. Seeded cohorts give the model a signal to learn and the agent a signal to explain. The cost: metrics describe this synthetic set only. Evidence: `card_transaction_bronze_generator.ipynb`; `prompts/step1_3458967129203277.md`.
* **JSON bronze with 15% DQ errors.** I chose realistic dirty landing data (duplicates, null `txn_id`, null `customer_id`) over clean data, so silver expectations and dedup get tested. 17,932 transaction rows are dropped by expectations. Evidence: `logs/update_60f6d1de_full_refresh_2026-10-15.md`.
* **Spark Declarative Pipeline, not plain jobs.** Bronze, silver and gold run in pipeline c0db28b8, with Auto Loader and expectations. The job only orchestrates it. Evidence: `FE BAR Bronze Silver AutoLoader Pipeline.sql`, `gold_feature_layer.sql`.

## Lakebase

* **SNAPSHOT sync, not Triggered.** Triggered sync failed on the MVs with `MATERIALIZED_VIEW_CDF_REQUIRES_EXTERNAL_METADATA`. The gold MVs are fully recomputed on each refresh, so a snapshot is equivalent. The cost: a full copy per sync. Evidence: `logs/lakebase_sync_2026-10-17.md` "Why SNAPSHOT".
* **Synced tables in their own catalog `fe_bar_lakebase`.** I chose this over `fe_bar_a0`, so the Postgres layout (`fraud`, `fraud_gov`, `cases`, `fraud_dash`) shows in UC unchanged. Evidence: `logs/lakebase_sync_2026-10-17.md` "Infrastructure".
* **Postgres FGAC through views and RLS.** Synced tables cannot take RLS, so `fraud_gov` security_barrier views apply the row and column rules and no role has a grant on `fraud.*`. `cases.*` uses FORCE RLS, and `db_inserted_by DEFAULT session_user` stops spoofed attribution. I did not sync a pre-filtered UC view, because that needs a copy per persona and cannot do a per-user filter. Evidence: `lakebase_fgac.sql`, `logs/lakebase_fgac_2026-10-21.md`, `logs/agent_governance_2026-10-21.md` Items 4 and 7.

## Model and agent

* **LightGBM and a time split.** LightGBM handles the 3 categoricals, takes `scale_pos_weight` (41.2584) and gives exact TreeSHAP for the top-3 signals. I split by time (cutoff 2026-09-21 15:20:18), not at random, so the test set is later than training. Evidence: `logs/ml_training_2026-10-20.md`.
* **Thresholds from MLflow.** Block = lowest score with test precision >= 0.50 (0.950267). Review = highest score with cumulative recall >= 0.60 (0.871416). Both are MLflow params, read at scoring time and in `validation_notebooks/business_value.ipynb`, never hardcoded. Evidence: `logs/ml_training_2026-10-20.md` "Thresholds".
* **Cohort lift check.** The cohort has a 9.70x lift but is 1.0% of the top 500 scores, and non-cohort PR-AUC is 0.2809. So the model learned more than the seeded rule. Evidence: `logs/ml_training_2026-10-20.md` "Seeded cohort lift".
* **Calibrated confidence.** I replaced the 0.03 placeholder with observed precision per score bucket in `risk_score_calibration`. TXN-0234209 moved from high to medium. Evidence: `logs/agent_governance_2026-10-21.md` Item 8.
* **Agent tools in Python under `SET ROLE fraud_triage_agent`.** UC functions cannot get a Lakebase credential, and UC reads see 0 case rows through RLS. So all four tools run agent-side with the same names. `create_fraud_case` is idempotent. Evidence: `logs/fgac_hardening_2026-10-21.md` Item 5; `fraud_triage_agent.py`.

## Dashboard, Genie Agent and governance

* **Dashboard reads `fraud_dash` views.** The UC path runs as `databricks_reader_17063` and cannot tell viewers apart. So the views are non-pii safe, pre-aggregated, and never select `notes`, `created_by` or `db_inserted_by`. Evidence: `lakebase_dashboard.sql`, `logs/dashboard_2026-10-22.md` "UC Reader Role".
* **Genie Agent reads only the six `fraud_dash` views and `risk_score_calibration`.** In Step 8, `scored_transactions` and `txn_features_gold` had no row filter and showed 751 rows over $10,000, so I did not attach them. I also fixed `fraud_dash.triage_queue` to blank the `amt_to_monthly_spend` value in `top_shap_signals`, which would have revealed the masked monthly spend. The cost: the space cannot answer merchant-category or monthly-spend questions. Evidence: `logs/genie_agent_2026-11-03.md` "Governance findings and decisions"; `genie/fraud_risk_ops_genie.json`.
* **Row filter on gold, a mask on `avg_amount_30d`, and least privilege for `account users`.** Step 8 found gold had no filter and `account users` had ALL PRIVILEGES and MANAGE on the shared catalog. I added the filter and mask and narrowed `account users` on `fe_bar_a0` to USE SCHEMA plus SELECT on 4 objects. I revoked SELECT on `customer_risk_profile_gold`, whose counts let a reader infer hidden high-value transactions (151 customers). I dropped the row filter on `scored_transactions` again, because synced tables cannot read a filtered source. The cost: schemas created later are not readable by everyone. Evidence: `logs/gold_governance_2026-11-04.md`; `validation_notebooks/gold_governance_hardening.ipynb`; `validation_notebooks/catalog_grant_narrowing.ipynb`.
* **`fraud_dash` filters high-value rows instead of redacting them. This is open.** The views drop amount > 10000 for everyone. That was the simple non-pii-safe choice for a reader role that is not identity-aware. The cost: 705 flagged high-value transactions (200 fraud, $3,588,732.92) cannot be triaged in Genie, the dashboard or the App. Redacting the amount or a pii-only view schema is not built. Evidence: `logs/gold_governance_2026-11-04.md` "Still open"; `logs/business_value_2026-11-06.md` "B.4b-1".

## Databricks App

* **Direct UC grants for the App service principal, not group membership.** `uc_app_grants.sql` grants exactly what the app reads: SELECT on the six `fraud_dash` views and `risk_score_calibration`. The service principal is in no other group. It has no SELECT on `scored_transactions`, `txn_features_gold` or `customer_risk_profile_gold` (PASS). The cost: grants are kept per principal. The log records this scope; it does not record a written comparison with group membership. Evidence: `logs/app_2026-11-04.md` "UC grants for the service principal"; `uc_app_grants.sql`.
* **Agent runs in-process in the App, not on a Model Serving endpoint.** MLflow's `DatabricksLakebase` resource only accepts a provisioned `database_instance_name`, and `fe-bar-fraud-analytics` is an Autoscaling project. The cost: the registered agent (@champion v3) is not deployed, and the app imports the shared modules. Evidence: `logs/app_2026-11-04.md` "Design (approved in Part B)".
* **The App acts as its own Postgres role.** The service principal's role is a member of `fraud_triage_agent` only, with no superuser, BYPASSRLS or direct table grants. So `db_inserted_by` tells the app apart from a human: case 5af3575c has the app role. The cost: no per-user (OBO) attribution. Evidence: `logs/app_2026-11-04.md` "Postgres identity and grant (B.4a)"; `lakebase_fgac_hardening.sql` Item 9.
* **Streamlit, not FastAPI.** It is an internal, widget-driven analyst tool with no REST consumers. Evidence: `logs/app_2026-11-04.md` "Design (approved in Part B)".
