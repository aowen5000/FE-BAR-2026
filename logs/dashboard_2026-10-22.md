# Dashboard validation log — 2026-10-22

Workspace: fevm-workshop-guy. Genie conversation ID: 1835980093459154. Branch: feature/fraud-ops-dashboard.
Dashboard: FE Bar Fraud Ops: Triage & Action (`01f1ce7f835a1e81b05ebb664bf0994c`).
Warehouse: `9bbc027402111984` (Statement Execution API, embed credentials).
Lakebase: project fe-bar-fraud-analytics / branch production / database fe_bar_db, UC catalog fe_bar_lakebase.
Notebook evidence: `validation_notebooks/dashboard_validation.ipynb` (15/15 cells with outputs, serverless).
Dates are UTC (2026-10-22 / 2026-10-23 for the run timestamp).

## Infrastructure

* **fraud_dash schema** created in fe_bar_db (lakebase_dashboard.sql, also appended as B.4 in lakebase_fgac.sql).
* Views owned by fraud_lead (uses fraud_lead RLS), all security_barrier, explicit `amount <= 10000` filter:
  - `fraud_dash.case_summary` — case lifecycle (fraud_lead sees all rows; reader sees amount ≤ 10K)
  - `fraud_dash.case_actions_daily` — daily action aggregates
  - `fraud_dash.score_distribution` — risk score histogram with thresholds from model_thresholds
  - `fraud_dash.exposure` — exposure by band and risk tier
  - `fraud_dash.baseline_comparison` — model vs baseline rule performance
  - `fraud_dash.triage_queue` — ranked triage list with SHAP signals (LATERAL lookups)
* Table: `fraud_dash.model_thresholds` (loaded from MLflow run d89beaca by notebook D.1)
* Dashboard published with embed credentials on warehouse 9bbc027402111984.
* Exported to repo: `dashboards/fe_bar_fraud_ops.lvdash.json` (draft object).

## UC Reader Role

* Reader identity: `databricks_reader_17063` (fe_bar_db OID 17063).
* Confirmed via pg_stat_activity during a live UC query.
* No superuser, no bypassrls, no role memberships.
* Already had SELECT on cases.*/fraud.* (Lakebase default ACL grants reader on new objects) — flagged, not changed.

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

All tests run as UC reader (`databricks_reader_17063`):

1. RLS hides raw case rows (cases.fraud_cases via UC = 0 rows)
2. `notes` column not in fraud_dash views
3. `created_by` column not in fraud_dash views
4. `db_inserted_by` column not in fraud_dash views
5. INSERT on fraud_dash rejected
6. UPDATE on fraud_dash rejected
7. DELETE on fraud_dash rejected
8. INSERT on cases.fraud_cases rejected
9. Reader has zero write privileges across all schemas

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

All p95 under 7 seconds. ds_score_dist and ds_exposure are the heaviest (full-table scans with threshold joins).

## Live-Read Proof (D.2)

Agent invoked exactly once for TXN-0350980. No sync/job between the before and after snapshots.

* **Case created:** 030dc7fb-3284-4cc2-9264-06b7de57c2cb at 01:45:33 UTC
* **BEFORE** (01:45:19 UTC): cases_created_today=0, open_cases=6, visible_cases=164
* **AFTER** (01:45:41 UTC): cases_created_today=1, open_cases=7, visible_cases=165

Timestamps:

| Step | UTC |
| --- | --- |
| 0_start | 01:45:16.902 |
| 1_before | 01:45:19.330 |
| 2_candidate | 01:45:22.177 |
| 3_agent_done | 01:45:39.286 |
| 4_after | 01:45:41.481 |
| 5_case_row | 01:45:42.658 |

Agent latency (candidate → done): ~17s. Dashboard reflected the new case within 2s of agent completion.

## End-to-End Trace (D.3)

TXN-0234209 traced through all 8 hops:

1. raw bronze (AutoLoader)
2. silver (dedup + expectations)
3. gold (feature join)
4. scored (LightGBM pyfunc)
5. Lakebase synced (fraud.txn_risk_current)
6. Lakebase governed (fraud_gov.txn_risk_current → fraud_dash views)
7. Agent case (fraud_triage_agent → cases.fraud_cases)
8. Dashboard (fraud_dash.case_summary)

## Files

* `lakebase_dashboard.sql` — fraud_dash schema DDL (new)
* `lakebase_fgac.sql` — B.4 section appended (identical to lakebase_dashboard.sql)
* `dashboards/fe_bar_fraud_ops.lvdash.json` — dashboard export (new)
* `validation_notebooks/dashboard_validation.ipynb` — 15 cells with outputs (new)
* `logs/dashboard_dataset_results_2026-10-22.md` — 10 dataset SQL + results (written by notebook)
* `logs/dashboard_2026-10-22.md` — this file
