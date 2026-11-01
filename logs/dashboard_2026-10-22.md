# Dashboard validation log — 2026-10-22

Workspace: fevm-workshop-guy. Genie conversation ID: 1835980093459154. Date: 2026-10-22.
Branches: feature/fraud-ops-dashboard (commit 7349425, merged to main as ee35a48), then step6/2026-10-22_fevm-workshop-guy_conv-1835980093459154 (this correction).
Dashboard: FE Bar Fraud Ops: Triage & Action (`01f1ce7f835a1e81b05ebb664bf0994c`).
Warehouse: `9bbc027402111984` (Statement Execution API, embed credentials).
Lakebase: project fe-bar-fraud-analytics / branch production / database fe_bar_db, UC catalog fe_bar_lakebase.
Dates are UTC (the interactive run happened at 2026-10-23 01:4x UTC, which is 2026-10-22 local).

## Evidence status (corrected 2026-10-22)

* `validation_notebooks/dashboard_validation.ipynb` ran interactively on serverless, and all 15 code cells passed. The outputs were kept only in the workspace notebook object (ID 1835980093459164). The committed `.ipynb` in 7349425 has no outputs.
* When the git folder was switched between branches with the Repos API, the workspace rebuilt the notebook from git under a new ID (2932538792700906). The original object and its outputs were lost and could not be recovered.
* Evidence that the interactive run happened: the version of `logs/dashboard_dataset_results_2026-10-22.md` in commit 7349425, written by cell D.1 (10 datasets, warehouse statement IDs). Postgres also has case 030dc7fb-3284-4cc2-9264-06b7de57c2cb, written by the agent in D.2, and MLflow has trace tr-a378f1a1b9d34fc7e7e7bf911599b31b.
* Re-run for evidence: job run 659281894932228 (one-time submit, serverless). Its first task attempt (1111349178305485) failed with SIGABRT in the setup cell. Serverless retried automatically, and attempt 403680627357199 ran all 16 cells (02:22:28 to 02:43:20 UTC on 2026-10-23). Cell outputs are in `logs/dashboard_validation_run_659281894932228.md`, which GitHub renders, and in the raw export `logs/dashboard_validation_run_659281894932228.html`. This run rewrote `logs/dashboard_dataset_results_2026-10-22.md` (now "Run at 2026-10-23 02:42:19.734 UTC").
* The re-run's D.2 cell created one more real case: c2b2ec3a-a1a7-444f-a1c8-969af362c0ee (TXN-0197951, CUST-04108, amount 113.99, open, auto_block, created 02:42:37.630 UTC, trace tr-6659ce2b852915f489c9add9eef92cbd). It was left open.
* A second submitted run, 1080711831453220, was cancelled on the user's instruction before it reached D.2, so it created no case.
* The numbers below come from the interactive run as recorded in the conversation. Details in an earlier version of this file that could not be traced to a recorded output were removed: the per-test deny wording, the step timestamp table, the case creation time, the agent latency, and the descriptions of the pipeline layers.

## Infrastructure

* **fraud_dash schema** created in fe_bar_db (lakebase_dashboard.sql, also appended as B.4 in lakebase_fgac.sql).
* Views owned by fraud_lead (uses fraud_lead RLS), all security_barrier, explicit `amount <= 10000` filter:
  - `fraud_dash.case_summary` — case lifecycle (fraud_lead sees all rows; reader sees amount ≤ 10K)
  - `fraud_dash.case_actions_daily` — daily action aggregates
  - `fraud_dash.score_distribution` — risk score histogram with thresholds from model_thresholds
  - `fraud_dash.exposure` — by (recommended_action, is_fraud), with fraud_amount_caught / fraud_amount_missed
  - `fraud_dash.baseline_comparison` — model vs baseline rule (is_cross_border = 1 AND is_new_device = 1)
  - `fraud_dash.triage_queue` — ranked triage list with SHAP signals (LATERAL lookups)
* Table: `fraud_dash.model_thresholds` (loaded from MLflow run d89beaca by notebook cell B.0)
* Dashboard published with embed credentials on warehouse 9bbc027402111984.
* Exported to repo: `dashboards/fe_bar_fraud_ops.lvdash.json` (draft object).

## UC Reader Role

* Reader identity: `databricks_reader_17063` (fe_bar_db OID 17063).
* Confirmed via pg_stat_activity during a live UC query.
* No superuser, no bypassrls, no role memberships.
* Already had table-level SELECT on cases.fraud_cases, including the notes, created_by and db_inserted_by columns. This comes from Lakebase default privileges. FORCE RLS still returns 0 rows through UC because the reader has no policy. Flagged, not changed.

## Case Counts and FGAC

| Source | Path | Visible rows |
| --- | --- | --- |
| UC raw cases.fraud_cases | Through UC (reader) | 0 (RLS hides all) |
| fraud_dash.case_summary | Through UC (reader) | 164 |
| fraud_lead Postgres (SET ROLE) | Direct Postgres | 169 |
| **Difference** | | **5** (exactly the 5 high-amount cases with amount > $10K) |

The 5-row gap matches the FGAC row filter: fraud_dash views enforce `amount <= 10000`; fraud_lead sees all 169 via direct Postgres.

## Model Thresholds

* block_threshold: 0.9503 (from MLflow run d89beaca8f81447780da60ed2ea7c811)
* review_threshold: 0.8714

## Deny Tests (9/9 PASS)

Run through UC as the reader (`databricks_reader_17063`). The 9 tests covered three things: raw case rows are hidden, the notes / created_by / db_inserted_by columns are absent from fraud_dash, and writes are rejected. The per-test output was in the lost notebook object.

## Dataset Latency (serverless through UC, 20 runs each)

| Dataset | p50 ms | p95 ms |
| --- | --- | --- |
| ds_kpi_cases | 2129 | 4074 |
| ds_model_vs_baseline | 3668 | 5804 |
| ds_score_dist | 5845 | 6091 |
| ds_cases_daily | 3209 | 5271 |
| ds_actions_daily | 2131 | 3148 |
| ds_triage | 2918 | 5877 |
| ds_triage_options | 4946 | 5924 |
| ds_recent_cases | 2004 | 3126 |
| ds_calibration | 2113 | 4181 |
| ds_exposure | 5139 | 6359 |

In the interactive run (2026-10-23 01:4x UTC, 2026-10-22 local; notebook object 1835980093459164), all p95 values in this table are under 7 seconds. ds_score_dist and ds_exposure are the slowest. The re-run below (job run 659281894932228) measured higher values.

## Live-Read Proof (D.2)

Agent invoked exactly once for TXN-0350980. No sync/job between the before and after snapshots.

* **Case created:** 030dc7fb-3284-4cc2-9264-06b7de57c2cb (agent trace tr-a378f1a1b9d34fc7e7e7bf911599b31b)
* Re-checked 2026-10-23 02:43 UTC: fe_bar_lakebase.fraud_dash.case_summary returns this case (TXN-0350980, open, auto_block, created_at 2026-10-23 01:45:33.754 UTC). mlflow.get_trace returns the trace with state OK.
* **BEFORE** (01:45:19 UTC): cases_created_today=0, open_cases=6, visible_cases=164
* **AFTER** (01:45:41 UTC): cases_created_today=1, open_cases=7, visible_cases=165
* Agent tool `explain_top_signals` failed with `Unknown format code 'f' for object of type 'str'` (an existing bug in fraud_triage_agent.py). The case was still created, and the agent recorded the failure in the case notes.

## Re-run results (job run 659281894932228)

* Counts: dash_cases 165 through UC vs 170 as fraud_lead at B.1. The difference of 5 is the same 5 high-amount cases. Raw cases through UC = 0.
* Deny tests 9/9 PASS: count on cases.fraud_cases; notes/db_inserted_by on cases.fraud_cases and cases.case_actions; notes, created_by and db_inserted_by on fraud_dash.case_summary; INSERT into fraud_dash.model_thresholds; UPDATE on cases.fraud_cases; DELETE on fraud_dash.case_summary.
* Live read: TXN-0197951 -> case c2b2ec3a. BEFORE (02:42:24.965 UTC): cases_created_today=1, open_cases=7, visible_cases=165. AFTER (02:42:45.311 UTC): 2 / 8 / 166. No job 1115396029932218 run and no sync pipeline update in the window.
* Latency p50/p95 ms (20 runs): ds_kpi_cases 2126/5075, ds_model_vs_baseline 4801/8726, ds_score_dist 6869/8153, ds_cases_daily 4195/6324, ds_actions_daily 3074/5077, ds_triage 4851/5815, ds_triage_options 6058/8156, ds_recent_cases 2984/4161, ds_calibration 3101/4244, ds_exposure 6483/7845. Several p95 values are above 7 s in this run.
* The highest p95 in this re-run is 8726 ms (ds_model_vs_baseline). Both runs measured serverless SQL through UC on compute that was not fully warm. They do not measure Lakebase point-read latency, which is reported in `logs/lakebase_fgac_2026-10-21.md` and `validation_notebooks/lakebase_scores_validation.ipynb`.

## End-to-End Trace (D.3)

TXN-0234209 traced through all 8 hops:

1. raw/bronze (fact_transactions_bronze)
2. silver (fact_transactions_silver)
3. gold features (txn_features_gold)
4. score (scored_transactions): 0.9844, block
5. Lakebase synced (fraud.txn_risk_current)
6. Lakebase governed (fraud_gov.txn_risk_current)
7. agent case in Postgres: 2319d4b7-bea3-412b-ba6b-8325e1a7a71d, auto_block
8. dashboard (fraud_dash.case_summary)

## Files

* `lakebase_dashboard.sql` — fraud_dash schema DDL (new)
* `lakebase_fgac.sql` — B.4 section appended (identical to lakebase_dashboard.sql)
* `dashboards/fe_bar_fraud_ops.lvdash.json` — dashboard export (new)
* `validation_notebooks/dashboard_validation.ipynb` — 15 code cells (committed without outputs; see Evidence status)
* `logs/dashboard_dataset_results_2026-10-22.md` — 10 dataset SQL + results (written by notebook; current version from re-run 659281894932228)
* `logs/dashboard_validation_run_659281894932228.md` / `.html` — every cell's code and output from the re-run
* `logs/dashboard_2026-10-22.md` — this file
