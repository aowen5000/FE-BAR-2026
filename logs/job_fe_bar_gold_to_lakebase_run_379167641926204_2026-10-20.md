# Lakeflow Job Run Evidence — fe_bar_gold_to_lakebase (with batch scoring)

**Job ID:** `1115396029932218`  
**Run ID:** `379167641926204`  
**Date:** 2026-10-20  
**Workspace:** fevm-workshop-guy  
**Result:** TERMINATED / SUCCESS, total run duration 289.2s (start 1792470901439, end 1792471190603)

## Job configuration (updated 2026-10-20)

* **Task 1 (gold_pipeline_refresh):** Pipeline task, pipeline `c0db28b8-dbd2-432d-99cf-4ea2aea60274`, normal update (unchanged)
* **Task 2 (batch_scoring, NEW):** Notebook task `/Workspace/Users/alex.owen@databricks.com/FE-BAR-2026-repo/fraud_batch_scoring` (source WORKSPACE), serverless environment `scoring_env` (client 4, `lightgbm==4.7.0`), depends on task 1
* **Task 3 (lakebase_sync_refresh):** Pipeline task, pipeline `f8690359-4bb1-45b9-8fdb-5bd892239db2`, now depends on task 2. The pipeline includes `txn_features`, `customer_risk_profile`, and `txn_risk_current`.

## Per-task results

| Task | Task run ID | State | Start (ms) | End (ms) | Duration |
| --- | --- | --- | --- | --- | --- |
| gold_pipeline_refresh | 326817573218830 | SUCCESS | 1792470901477 | 1792470964270 | 62.8s |
| batch_scoring | 1077645683924475 | SUCCESS | 1792470964504 | 1792471137421 | 172.9s (setup 4s, exec 168s) |
| lakebase_sync_refresh | 982139009316385 | SUCCESS | 1792471137806 | 1792471190342 | 52.5s |

* **Task 1 pipeline update:** `34a5a929-6cd1-4a88-b883-0e8a30f6ef4e` (COMPLETED)
* **Task 3 sync update:** `a335e132-3102-4eac-adb4-be7e66fb82bc` (COMPLETED)

## Before/after comparison

| Metric | Before | After |
| --- | --- | --- |
| scored_transactions max(scored_at) | 2026-10-20 02:40:39.012983 UTC | **2026-10-20 04:38:02.628263 UTC** |
| scored_transactions rows | 464,632 | 464,632 |
| Lakebase fraud.txn_risk_current rows | 464,632 | 464,632 |
| Lakebase fraud.txn_risk_current max(scored_at) | 2026-10-20 02:40:39.012983 | 2026-10-20 04:38:02.628263 |
| txn_features_gold rows / Lakebase fraud.txn_features rows | 464,632 / 464,632 | 464,632 / 464,632 |
| customer_risk_profile_gold / Lakebase customer_risk_profile | 9,289 / 9,289 | 9,289 / 9,289 |
| gold max(txn_ts) | 2026-10-16 23:55:43 | 2026-10-16 23:55:43 |
| TXN-0234209 (UC and Lakebase) | 0.9844108757126732 / block | 0.9844108757126732 / block |

scored_at advanced and Lakebase now carries the new scored_at, so the scores were recomputed and pushed through the sync. Row counts did not change because no new source data arrived since the last gold refresh (gold max txn_ts is unchanged). For the same reason, `txn_features` and `customer_risk_profile` show their 2026-10-17 last_sync (source Delta version 11 unchanged), while `txn_risk_current` synced Delta version 4.

Raw JSON: `logs/job_run_379167641926204_raw_2026-10-20.json`, `logs/lakebase_scores_sync_raw_2026-10-20.json`.
