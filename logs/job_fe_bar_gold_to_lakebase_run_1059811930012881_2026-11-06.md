# Job fe_bar_gold_to_lakebase, run 1059811930012881 (2026-11-06)

Step 10, Part C. One run approved by the user. Workspace fevm-workshop-guy, serverless.
Genie Code conversation 1883459888084300.
This is the first green run since run 273696236528085 failed at lakebase_sync_refresh
(SOURCE_READ_ERROR / ROW_LEVEL_SECURITY_FEATURE_NOT_SUPPORTED.TIME_TRAVEL on scored_transactions).
The row filter on scored_transactions had been dropped (option B, logs/gold_governance_2026-11-04.md).
No retries. Nothing was changed before or during the run.

## Run

| Field | Value |
|---|---|
| Job ID | 1115396029932218 |
| Run ID | 1059811930012881 |
| Result | SUCCESS |
| Duration | 267 s |
| Run page | https://fevm-workshop-guy.cloud.databricks.com/?o=7474659392412718#job/1115396029932218/run/1059811930012881 |

## Tasks

| Task | Task run ID | Life cycle | Result | Duration |
|---|---|---|---|---|
| gold_pipeline_refresh | 1050818699563606 | TERMINATED | SUCCESS | 63 s |
| batch_scoring | 1086396456455747 | TERMINATED | SUCCESS | 151 s |
| lakebase_sync_refresh | 455481036519417 | TERMINATED | SUCCESS | 53 s |

## Pipeline updates started by this run

| Pipeline | Pipeline ID | Update ID | State | Cause | Full refresh |
|---|---|---|---|---|---|
| SDP bronze/silver/gold | c0db28b8-dbd2-432d-99cf-4ea2aea60274 | e07e06df-7470-473b-bf75-3941d56deba5 | COMPLETED | JOB_TASK | False |
| Lakebase sync | f8690359-4bb1-45b9-8fdb-5bd892239db2 | daedd8c1-5334-4287-a06d-154fe7cebe9f | COMPLETED | JOB_TASK | False |

## Synced tables after the run

| Synced table | State | Pipeline |
|---|---|---|
| fe_bar_lakebase.fraud.txn_features | SYNCED_TABLE_ONLINE_NO_PENDING_UPDATE | f8690359-4bb1-45b9-8fdb-5bd892239db2 |
| fe_bar_lakebase.fraud.customer_risk_profile | SYNCED_TABLE_ONLINE_NO_PENDING_UPDATE | f8690359-4bb1-45b9-8fdb-5bd892239db2 |
| fe_bar_lakebase.fraud.txn_risk_current | SYNCED_TABLE_ONLINE_NO_PENDING_UPDATE | f8690359-4bb1-45b9-8fdb-5bd892239db2 |
| fe_bar_lakebase.fraud.risk_score_calibration | SYNCED_TABLE_ONLINE_NO_PENDING_UPDATE | f8690359-4bb1-45b9-8fdb-5bd892239db2 |

## Row counts: UC = Postgres

| Object | Rows |
|---|---|
| UC workshop_guy_catalog.fe_bar_a0.scored_transactions | 464632 |
| UC fe_bar_lakebase.fraud.txn_risk_current | 464632 |
| Postgres fe_bar_db fraud.txn_risk_current | 464632 |
| All equal | True |

## Traced transaction TXN-0234209

| Read | risk_score | recommended_action | scored_at |
|---|---|---|---|
| UC scored_transactions, before the run | 0.9844108757126732 | block | 2026-11-04T00:44:40.881Z |
| UC scored_transactions, after the run | 0.9844108757126732 | block | 2026-11-06 23:46:56.753972 |
| Postgres fraud.txn_risk_current, after the run | 0.9844108757126732 | block | 2026-11-06 23:46:56.753972+00:00 |

risk_score unchanged vs pre-run 0.9844108757126732: True. Only scored_at moved, as expected for a re-score.

Method: Python SDK w.jobs.run_now / get_run, w.pipelines.list_updates, w.database.get_synced_database_table;
Postgres read with psycopg as alex.owen@databricks.com using an OAuth token from w.postgres.generate_database_credential.
