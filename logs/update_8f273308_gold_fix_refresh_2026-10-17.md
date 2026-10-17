# Pipeline Run Evidence — Selective Gold Refresh (CDF Removal)

**Update ID:** `8f273308-3190-4bb9-a3d5-1bbf1da91b1d`  
**Pipeline:** FE BAR Bronze Silver AutoLoader Pipeline  
**Pipeline ID:** `c0db28b8-dbd2-432d-99cf-4ea2aea60274`  
**State:** COMPLETED  
**Type:** Selective refresh: gold only  
**Start:** 1792199675285  
**Cluster:** serverless  
**Workspace:** fevm-workshop-guy  
**Date:** 2026-10-17  

## Changes in this update

1. **Removed CDF TBLPROPERTIES** from both gold MVs (`txn_features_gold`, `customer_risk_profile_gold`). CDF properties have no effect on SDP-managed materialized views; they were added then removed to avoid confusion.
2. **Confirmed passthrough columns** added in prior update (d4b5ad24): `geo_distance_from_home` (DOUBLE), `device_id` (STRING), `channel` (STRING) in `txn_features_gold`.
3. Gold MVs now have COMMENT clauses only, no TBLPROPERTIES.

## Dataset Results

| Dataset | Type | Rows |
| --- | --- | --- |
| `txn_features_gold` | MATERIALIZED_VIEW | 464,679 |
| `customer_risk_profile_gold` | MATERIALIZED_VIEW | 9,289 |

**Total rows written (gold):** 473,968  
**Columns in txn_features_gold:** 25 (including geo_distance_from_home, device_id, channel)

## Event Timeline (selected)

| Timestamp | Message |
| --- | --- |
| 2026-10-17T01:15:17.734Z | Update 8f2733 is COMPLETED. |
| 2026-10-17T01:15:17.682Z | Flow 'workshop_guy_catalog.fe_bar_a0.customer_risk_profile_gold' has COMPLETED. |
| 2026-10-17T01:15:13.795Z | Flow 'workshop_guy_catalog.fe_bar_a0.customer_risk_profile_gold' is RUNNING. |
| 2026-10-17T01:15:13.658Z | Flow 'workshop_guy_catalog.fe_bar_a0.customer_risk_profile_gold' is STARTING. |
| 2026-10-17T01:15:13.654Z | Flow 'workshop_guy_catalog.fe_bar_a0.customer_risk_profile_gold' has been planned to be executed as COMPLETE_RECOMPUTE. |
| 2026-10-17T01:15:12.978Z | Flow 'workshop_guy_catalog.fe_bar_a0.customer_risk_profile_gold' is PLANNING. |
| 2026-10-17T01:15:12.959Z | Flow 'workshop_guy_catalog.fe_bar_a0.txn_features_gold' has COMPLETED. |
| 2026-10-17T01:15:05.102Z | Flow 'workshop_guy_catalog.fe_bar_a0.txn_features_gold' is RUNNING. |
| 2026-10-17T01:15:04.967Z | Flow 'workshop_guy_catalog.fe_bar_a0.txn_features_gold' is STARTING. |
| 2026-10-17T01:15:04.946Z | Flow 'workshop_guy_catalog.fe_bar_a0.txn_features_gold' has been planned to be executed as COMPLETE_RECOMPUTE. |
| 2026-10-17T01:15:02.896Z | Flow 'workshop_guy_catalog.fe_bar_a0.txn_features_gold' is PLANNING. |
| 2026-10-17T01:15:02.877Z | Flow 'workshop_guy_catalog.fe_bar_a0.dim_merchant_bronze' is EXCLUDED. |
| 2026-10-17T01:15:02.876Z | Flow 'workshop_guy_catalog.fe_bar_a0.fact_transactions_bronze' is EXCLUDED. |
| 2026-10-17T01:15:02.874Z | Flow 'workshop_guy_catalog.fe_bar_a0.fact_prior_fraud_cases_bronze' is EXCLUDED. |
| 2026-10-17T01:15:02.873Z | Flow 'workshop_guy_catalog.fe_bar_a0.fact_prior_fraud_cases_silver' is EXCLUDED. |
| 2026-10-17T01:15:02.871Z | Flow 'workshop_guy_catalog.fe_bar_a0.dim_customer_bronze' is EXCLUDED. |
| 2026-10-17T01:15:02.869Z | Flow 'workshop_guy_catalog.fe_bar_a0.dim_customer_silver' is EXCLUDED. |
| 2026-10-17T01:15:02.867Z | Flow 'workshop_guy_catalog.fe_bar_a0.fact_transactions_silver' is EXCLUDED. |
| 2026-10-17T01:15:02.863Z | Flow 'workshop_guy_catalog.fe_bar_a0.dim_merchant_silver' is EXCLUDED. |
| 2026-10-17T01:15:02.853Z | Flow 'workshop_guy_catalog.fe_bar_a0.customer_risk_profile_gold' is QUEUED. |
