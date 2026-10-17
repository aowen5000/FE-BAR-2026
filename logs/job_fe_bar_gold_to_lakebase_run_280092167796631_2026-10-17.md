# Lakeflow Job Run Evidence — fe_bar_gold_to_lakebase

**Job ID:** `1115396029932218`  
**Run ID:** `280092167796631`  
**Date:** 2026-10-17  
**Workspace:** fevm-workshop-guy

## Job Configuration

* **Task 1 (gold_pipeline_refresh):** Pipeline task, pipeline `c0db28b8-dbd2-432d-99cf-4ea2aea60274`, normal update (not full refresh)
* **Task 2 (lakebase_sync_refresh):** Pipeline task, pipeline `f8690359-4bb1-45b9-8fdb-5bd892239db2`, depends on task 1

## Per-Task Results

| Task | State | Start | End |
| --- | --- | --- | --- |
| gold_pipeline_refresh | SUCCESS | 1792203954053 | 1792204056894 |
| lakebase_sync_refresh | SUCCESS | 1792204057143 | 1792204109663 |

* **Task 1 pipeline update:** `dabfee1b-29b6-4d9a-8b09-f98d14ef98e9` (COMPLETED)
* **Task 2 sync update:** `f95c31c4-979a-4d79-baab-50eb8594ec2b` (COMPLETED)

## Before/After Comparison

| Metric | Before | After |
| --- | --- | --- |
| txn_features rows | 464,679 | 464,632 |
| customer_risk_profile rows | 9,289 | 9,289 |
| max(txn_ts) | 2026-10-15 23:55:43+00:00 | 2026-10-16 23:55:43+00:00 |

Row counts changed because the gold MVs are fully recomputed with a rolling date window. The max txn_ts advanced by 1 day, confirming the pipeline processed new data and the sync refreshed Lakebase.

Postgres row counts match UC gold tables exactly after the sync.
