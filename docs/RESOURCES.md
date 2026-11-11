# Resources: repo layout and workspace inventory

Moved from README.md in Step 10. Workspace `fevm-workshop-guy`, serverless compute. 100% synthetic data.

## Layout

* Repo root: pipeline, model, agent and Lakebase source (notebooks, `.py` modules, `.sql` DDL).
* `README.md`, `EVIDENCE.md`, `EVIDENCE_APP.md`, `EVIDENCE_INDEX.md`, `DECISIONS.md`, `BUILD.md`: the short reading set.
* `docs/`: overflow detail (this file, `HOW_TO_RUN.md`, `TRACE.md`, `LIMITATIONS.md`, `CONVERSATION_IDS.md`).
* `validation_notebooks/`: check and verify notebooks with committed outputs.
  * `gold_feature_validation`: gold feature layer checks.
  * `lakebase_sync_validation`: gold to Lakebase synced tables.
  * `lakebase_write_path_validation`: `cases` schema write path (`lakebase_cases.py`).
  * `lakebase_scores_validation`: `fraud.txn_risk_current` read path and latency.
  * `lakebase_fgac_validation`: Postgres roles, `fraud_gov` views, RLS.
  * `fgac_hardening`: Step 5 hardening pass, items 1 to 8.
  * `dashboard_validation`: Step 6 dashboard dataset latency, FGAC deny tests, live-read proof, end-to-end trace.
  * `lineage_validation`: Step 7 table, column and model lineage from `system.access.*`.
  * `genie_agent_validation`: Step 8 Genie Agent pre-flight, governance check, creation, export, 11-question benchmark (Conversation API and native eval).
  * `gold_governance_hardening`: Step 8 follow-up, gold row filter and mask, job/sync test, `non_pii` access check.
  * `catalog_grant_narrowing`: Step 8 follow-up, `account users` narrowed to least privilege on `fe_bar_a0` (other schemas unchanged).
  * `app_validation`: Step 9 Databricks App: shared-module sha256, health check, before/after case state, attribution to the app's Postgres role, idempotency, UC visibility, Ask Genie vs `baseline_comparison`, guardrails through `app/`.
  * `business_value`: Step 10, read-only. Computes every $ and KPI number in README.md.
* `app/`: Databricks App `fe-bar-fraud-triage` (Streamlit): `app.py`, `app.yaml`, `requirements.txt` (exact pins), plus byte-identical copies of `fraud_triage_agent.py` and `lakebase_cases.py`.
* `scripts/sync_app_modules.py`: copies the two shared modules from the repo root into `app/` and checks their sha256.
* `dashboards/fe_bar_fraud_ops.lvdash.json`: exported Fraud Ops triage and action dashboard.
* `genie/fraud_risk_ops_genie.json`: exported FE Bar Fraud Risk Ops Genie space (sources, column configs, joins, snippets, examples, benchmarks).
* `genie_agent_benchmark_evidence_logs/`: per-identity Genie benchmark runs.
* `logs/`: run logs and evidence.

Validation notebooks import repo modules (for example `lakebase_cases`) from the repo root, one level above `validation_notebooks/`.

## Resource inventory

| Kind | Name | ID / detail |
| --- | --- | --- |
| UC catalog / schema | `workshop_guy_catalog.fe_bar_a0` | Shared catalog. `account users` has USE CATALOG / CREATE SCHEMA / BROWSE on it. On `fe_bar_a0` only USE SCHEMA plus SELECT on `fact_transactions_silver`, `dim_customer_silver`, `dim_merchant_silver` and `risk_score_calibration` (`customer_risk_profile_gold` revoked 2026-11-04 to close a count-inference leak). Source: `logs/gold_governance_2026-11-04.md` |
| UC volume | `workshop_guy_catalog.fe_bar_a0.staging` | Raw JSON: customers/, merchants/, transactions/, prior_fraud_cases/ |
| Bronze streaming tables | `dim_customer_bronze`, `dim_merchant_bronze`, `fact_transactions_bronze`, `fact_prior_fraud_cases_bronze` | In fe_bar_a0 |
| Silver MVs | `dim_customer_silver`, `dim_merchant_silver`, `fact_transactions_silver`, `fact_prior_fraud_cases_silver` | In fe_bar_a0 |
| UC row filter / column mask | `filter_high_amount_txns` on `fact_transactions_silver.amount` and `txn_features_gold.amount`; `mask_avg_monthly_spend` on `dim_customer_silver.avg_monthly_spend`; `mask_avg_amount_30d` on `customer_risk_profile_gold.avg_amount_30d` | Full access only for UC group `pii`. `scored_transactions` has no row filter: Lakebase synced tables cannot read a source with a table-level row filter (`logs/gold_governance_2026-11-04.md`). Re-checked 2026-11-06 in `information_schema.row_filters` / `column_masks` |
| Gold MVs | `txn_features_gold`, `customer_risk_profile_gold` | In fe_bar_a0 |
| Scored tables | `scored_transactions` (464,632 rows, PK txn_id), `risk_score_calibration` | In fe_bar_a0 |
| UC functions (deprecated) | `get_transaction_risk`, `explain_top_signals`, `get_customer_history` | `agent_tools.sql`; not registered with the agent since 2026-10-21 |
| SDP pipeline | FE BAR Bronze Silver AutoLoader Pipeline | `c0db28b8-dbd2-432d-99cf-4ea2aea60274` |
| Lakebase sync pipeline | SNAPSHOT synced tables | `f8690359-4bb1-45b9-8fdb-5bd892239db2` |
| Job | `fe_bar_gold_to_lakebase` | `1115396029932218`: gold_pipeline_refresh -> batch_scoring -> lakebase_sync_refresh. Last run 1059811930012881 SUCCESS (`logs/job_fe_bar_gold_to_lakebase_run_1059811930012881_2026-11-06.md`) |
| Lakebase | Project `fe-bar-fraud-analytics`, branch `production`, endpoint `primary`, database `fe_bar_db` | UC catalog `fe_bar_lakebase` |
| Lakebase schemas | `fraud` (synced, read-only), `fraud_gov` (governed views), `cases` (native OLTP: `fraud_cases`, `case_actions`), `fraud_dash` (dashboard views) | |
| Postgres roles | `fraud_pii`, `fraud_analyst`, `fraud_lead`, `fraud_triage_agent` (NOLOGIN group roles); UC reader `databricks_reader_17063`; app login role `8f239f44-078a-4f8f-90f1-4c1b0bcdc26c` (member of `fraud_triage_agent` only) | `lakebase_fgac.sql`, `lakebase_fgac_hardening.sql` (Item 9: app role grant) |
| Model | `workshop_guy_catalog.fe_bar_a0.fraud_risk_model` @champion = v1 | Run `d89beaca8f81447780da60ed2ea7c811`, experiment `/Users/alex.owen@databricks.com/fe_bar_fraud_risk_model` |
| Agent | `workshop_guy_catalog.fe_bar_a0.fraud_triage_agent` @champion = v3 (2026-11-01) | Run `d25dfe72e129478a8e17c0d6dbc7d433`, experiment `/Users/alex.owen@databricks.com/fe_bar_fraud_triage_agent`. Logged from `fraud_triage_agent.py` with `lakebase_cases.py` as a code path. Declared resource: serving endpoint `databricks-claude-sonnet-5-5`. Used, not declared: Lakebase `fe_bar_db` (project `fe-bar-fraud-analytics`, branch `production`, endpoint `primary`, role `fraud_triage_agent`). No UC functions. Registered, not deployed. v2 (run `97bc6c9b4e654abab627cd25ee93fa53`, pre-hardening UC-function tools) kept without an alias |
| Dashboard | FE Bar Fraud Ops: Triage & Action | `01f1ce7f835a1e81b05ebb664bf0994c`, warehouse `9bbc027402111984`, definition `dashboards/fe_bar_fraud_ops.lvdash.json` |
| Genie Agent (Genie space) | FE Bar Fraud Risk Ops | `01f1d7b464d510b9aa6cde48300787ca`, warehouse `9bbc027402111984`, folder `/Users/alex.owen@databricks.com/FE Bar Genie`, definition `genie/fraud_risk_ops_genie.json`. Governed sources only: `fe_bar_lakebase.fraud_dash.{triage_queue, case_summary, case_actions_daily, exposure, baseline_comparison, score_distribution}` and `fe_bar_a0.risk_score_calibration`. Account group `non_pii` has USE CATALOG / USE SCHEMA / SELECT on the six `fraud_dash` views. CAN_RUN (permissions API, 2026-11-06): app service principal and the non_pii test user (user ID 72697000497660) directly; the `non_pii` group has none. Evidence `logs/genie_agent_2026-11-03.md` |
| Databricks App | `fe-bar-fraud-triage` (Streamlit) | https://fe-bar-fraud-triage-7474659392412718.aws.databricksapps.com; source `app/`; active deployment `01f1d98ebd6c1954bd2d4b7f9d7c6ae5`. Service principal `app-1xzuu6 fe-bar-fraud-triage` (ID 72319122930742, application ID `8f239f44-078a-4f8f-90f1-4c1b0bcdc26c`). Resources: Lakebase database `fe-bar-db` (CAN_CONNECT_AND_CREATE), serving endpoint `databricks-claude-sonnet-5-5` (CAN_QUERY), Genie space `01f1d7b464d510b9aa6cde48300787ca` (CAN_RUN), warehouse `9bbc027402111984` (CAN_USE). UC grants in `uc_app_grants.sql` (SELECT on the six `fraud_dash` views and `risk_score_calibration` only). Pages: triage queue, transaction detail (Explain / Open case through the in-process agent), Ask Genie, dashboard link. Evidence `logs/app_2026-11-04.md`, `logs/app_deployment_2026-11-04.md` |
