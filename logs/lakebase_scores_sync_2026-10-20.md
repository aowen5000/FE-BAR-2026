# Lakebase Scores Sync Evidence — txn_risk_current (SNAPSHOT read path)

**Date:** 2026-10-20  
**Workspace:** fevm-workshop-guy  
**Validation notebook:** `lakebase_scores_validation.ipynb`

## Synced table

| Property | Value |
| --- | --- |
| Synced table | `fe_bar_lakebase.fraud.txn_risk_current` |
| Source | `workshop_guy_catalog.fe_bar_a0.scored_transactions` |
| Primary key | `txn_id` |
| Mode | SNAPSHOT |
| Project / branch | `fe-bar-fraud-analytics` / `production` |
| Database | `fe_bar_db` (Postgres table `fraud.txn_risk_current`) |
| Sync pipeline | `f8690359-4bb1-45b9-8fdb-5bd892239db2` (**reused**, via `existing_pipeline_id`) |
| State | SYNCED_TABLE_ONLINE_NO_PENDING_UPDATE |
| Endpoint | primary, ACTIVE, 1 CU min/max, scale-to-zero 300s (unchanged) |

The existing pipeline was reused, so no new pipeline was created. The SDK spec supports `existing_pipeline_id`, and the pipeline now carries `txn_features`, `customer_risk_profile`, and `txn_risk_current`.

After `create_synced_table`, the table stayed `SYNCED_TABLE_OFFLINE` until the pipeline ran. I started update `31370778-aca4-4b74-8a0c-062e953c4a3e` with the SDK (`w.pipelines.start_update`; the CLI `pipelines start-update` is blocked by the agent guardrail). It completed in about 50s and the table went ONLINE. `customer_risk_profile` behaved the same way on 2026-10-17.

## Postgres schema

| Column | Postgres type |
| --- | --- |
| txn_id (PK) | text |
| customer_id | text |
| txn_ts | timestamp with time zone |
| amount | double precision |
| risk_score | double precision |
| recommended_action | text |
| top_shap_signals | text |
| model_version | text |
| scored_at | timestamp with time zone |

## Row count match

| Store | Rows | max scored_at |
| --- | --- | --- |
| UC scored_transactions | 464,632 | 2026-10-20 02:40:39.012983 |
| Postgres fraud.txn_risk_current | 464,632 | 2026-10-20 02:40:39.012983+00:00 |

Match: True (model_version 1..1). After job run 379167641926204 both are still 464,632, with scored_at 2026-10-20 04:38:02.628263.

## Traced transaction TXN-0234209

| Field | UC | Postgres | Match |
| --- | --- | --- | --- |
| risk_score | 0.9844108757126732 | 0.9844108757126732 | True |
| recommended_action | block | block | True |
| model_version | 1 | 1 | True |

Postgres top_shap_signals: `[{"feature": "is_new_device", "value": 1.0, "shap": 2.5724}, {"feature": "geo_distance_from_home", "value": 450.63, "shap": 1.8741}, {"feature": "is_online", "value": 1.0, "shap": 1.2001}]`

## Read latency (200 primary-key lookups, one reused connection, OAuth token via `lakebase_cases.LakebaseCases`)

10 warm-up lookups excluded. 200 of 200 lookups hit.

| Metric | Latency |
| --- | --- |
| p50 | 2.10 ms |
| p95 | 3.18 ms |
| p99 | 4.38 ms |
| mean | 2.29 ms |
| max | 11.92 ms |

Raw JSON: `logs/lakebase_scores_sync_raw_2026-10-20.json`.
