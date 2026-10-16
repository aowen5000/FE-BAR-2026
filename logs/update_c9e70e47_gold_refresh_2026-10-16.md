# Pipeline Run Evidence — Selective Gold Refresh

**Update ID:** `c9e70e47-f29b-4044-8b78-69fc9227cb11`  
**Pipeline:** FE BAR Bronze Silver AutoLoader Pipeline  
**Pipeline ID:** `c0db28b8-dbd2-432d-99cf-4ea2aea60274`  
**State:** COMPLETED  
**Type:** Selective refresh: gold only  
**Start:** 2026-10-16T03:00:18.080Z  
**End:** 2026-10-16T03:00:52.762Z  
**Duration:** ~35 seconds  
**Cluster:** `1016-025543-t19sqsve-v2n`  
**Genie Conversation ID:** (placeholder)  
**Workspace:** fevm-workshop-guy  
**Date:** 2026-10-16  

## Pipeline Configuration

| Setting | Value |
| --- | --- |
| Catalog | `workshop_guy_catalog` |
| Schema | `fe_bar_a0` |
| Edition | ADVANCED |
| Channel | CURRENT |
| Photon | true |
| Serverless | true |
| Continuous | false |
| Development | false |
| Pipeline Type | WORKSPACE |

## Dataset Results

| Dataset | Type | Status | Rows Written | Rows Dropped |
| --- | --- | --- | --- | --- |
| `txn_features_gold` | MATERIALIZED_VIEW | COMPLETED | 464,679 | 0 |
| `customer_risk_profile_gold` | MATERIALIZED_VIEW | COMPLETED | 9,289 | 0 |

**Total rows written (gold):** 473,968  
**Total rows dropped by expectations:** 0  

## Data Quality Expectation Results

| Dataset | Constraint | Passed | Failed |
| --- | --- | --- | --- |
| `txn_features_gold` | valid_txn_ts (txn_ts IS NOT NULL) | 464,679 | 0 |
| `txn_features_gold` | positive_amount (amount > 0) | 464,679 | 0 |

## Bronze and Silver Refresh Status

**Bronze and silver tables were NOT refreshed in this update.** All 8 bronze/silver datasets were EXCLUDED from the selective refresh:

- `dim_customer_bronze` — EXCLUDED
- `dim_merchant_bronze` — EXCLUDED
- `fact_transactions_bronze` — EXCLUDED
- `fact_prior_fraud_cases_bronze` — EXCLUDED
- `dim_customer_silver` — EXCLUDED
- `dim_merchant_silver` — EXCLUDED
- `fact_transactions_silver` — EXCLUDED
- `fact_prior_fraud_cases_silver` — EXCLUDED

## Event Timeline

| Time (UTC) | Flow | Event |
| --- | --- | --- |
| 03:00:18.024 | — | Principal started update |
| 03:00:18.080 | — | Update c9e70e created by API_CALL |
| 03:00:28.323 | — | Runtime environment resolved |
| 03:00:28.873 | — | Update c9e70e INITIALIZING |
| 03:00:34.685 | — | Update c9e70e SETTING_UP_TABLES |
| 03:00:39.540 | dim_merchant_bronze | Flow defined as APPEND |
| 03:00:39.562 | fact_prior_fraud_cases_bronze | Flow defined as APPEND |
| 03:00:39.564 | dim_customer_bronze | Flow defined as APPEND |
| 03:00:39.567 | dim_customer_silver | Flow defined as MATERIALIZED_VIEW |
| 03:00:39.579 | dim_merchant_silver | Flow defined as MATERIALIZED_VIEW |
| 03:00:39.581 | fact_transactions_bronze | Flow defined as APPEND |
| 03:00:39.584 | fact_transactions_silver | Flow defined as MATERIALIZED_VIEW |
| 03:00:39.611 | txn_features_gold | Flow defined as MATERIALIZED_VIEW |
| 03:00:39.627 | fact_prior_fraud_cases_silver | Flow defined as MATERIALIZED_VIEW |
| 03:00:39.631 | customer_risk_profile_gold | Flow defined as MATERIALIZED_VIEW |
| 03:00:39.779 | — | Dataflow graph loaded |
| 03:00:39.784 | — | Update c9e70e RUNNING |
| 03:00:39.793 | txn_features_gold | QUEUED |
| 03:00:39.796 | customer_risk_profile_gold | QUEUED |
| 03:00:39.804 | dim_merchant_silver | EXCLUDED |
| 03:00:39.807 | fact_transactions_silver | EXCLUDED |
| 03:00:39.808 | dim_customer_silver | EXCLUDED |
| 03:00:39.809 | dim_customer_bronze | EXCLUDED |
| 03:00:39.810 | fact_prior_fraud_cases_silver | EXCLUDED |
| 03:00:39.811 | fact_transactions_bronze | EXCLUDED |
| 03:00:39.811 | fact_prior_fraud_cases_bronze | EXCLUDED |
| 03:00:39.812 | dim_merchant_bronze | EXCLUDED |
| 03:00:39.826 | txn_features_gold | PLANNING |
| 03:00:41.481 | txn_features_gold | COMPLETE_RECOMPUTE planned |
| 03:00:41.495 | txn_features_gold | STARTING |
| 03:00:41.598 | txn_features_gold | RUNNING |
| 03:00:48.299 | txn_features_gold | MV created |
| 03:00:48.367 | txn_features_gold | COMPLETED |
| 03:00:48.391 | customer_risk_profile_gold | PLANNING |
| 03:00:49.147 | customer_risk_profile_gold | COMPLETE_RECOMPUTE planned |
| 03:00:49.160 | customer_risk_profile_gold | STARTING |
| 03:00:49.275 | customer_risk_profile_gold | RUNNING |
| 03:00:52.690 | customer_risk_profile_gold | MV created |
| 03:00:52.737 | customer_risk_profile_gold | COMPLETED |
| 03:00:52.762 | — | Update c9e70e COMPLETED |

## Source

File: `/Workspace/Users/alex.owen@databricks.com/FE-BAR-2026-repo/gold_feature_layer.sql`
