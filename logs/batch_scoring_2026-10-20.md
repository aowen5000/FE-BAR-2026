# Batch Scoring Evidence — scored_transactions (Layer 3)

**Date:** 2026-10-20  
**Workspace:** fevm-workshop-guy  
**Notebook:** `fraud_batch_scoring.ipynb` (serverless; also job task `batch_scoring`)  
**Model:** `models:/workshop_guy_catalog.fe_bar_a0.fraud_risk_model@champion` → version 1, run `d89beaca8f81447780da60ed2ea7c811`  
**Target:** `workshop_guy_catalog.fe_bar_a0.scored_transactions` (managed Delta, INSERT OVERWRITE each run, PRIMARY KEY `scored_transactions_pk` on `txn_id NOT NULL`)

## Inputs read from the champion run params (nothing hardcoded)

| Param | Value |
| --- | --- |
| block_threshold | 0.950267 |
| review_threshold | 0.871416 |
| cohort_amt_ratio_p90 | 0.5442 |

Pre-flight check repeated: pii = True, 464,632 rows, 751 rows with amount > 10000, 431,471 non-null amt_to_monthly_spend → PASSED.

Scoring: LightGBM booster distributed via `mapInPandas` (64 partitions) with per-row TreeSHAP (`pred_contrib`); top 3 features by abs SHAP stored as JSON. Consistency check: max |registered pyfunc predict - distributed score| on 1,000 rows = **0.0**.

## Row counts

| Table | Rows |
| --- | --- |
| txn_features_gold | 464,632 |
| scored_transactions | 464,632 |
| Match | True |

Notebook write: Delta version 1, 64 files, 464,632 output rows, scored_at 2026-10-20 02:40:39 UTC.

## recommended_action distribution

| Action | Txns | % |
| --- | --- | --- |
| approve | 439,726 | 94.640% |
| review | 22,821 | 4.912% |
| block | 2,085 | 0.449% |

## risk_score percentiles

| Percentile | risk_score |
| --- | --- |
| p1 | 0.046219 |
| p10 | 0.118036 |
| p25 | 0.141327 |
| p50 | 0.168246 |
| p75 | 0.209630 |
| p90 | 0.336641 |
| p95 | 0.875660 |
| p99 | 0.943038 |
| p99.9 | 0.987018 |
| min / max | 0.003545 / 0.993762 |

## Top 10 highest-risk transactions

| txn_id | customer_id | txn_ts | amount | risk_score | action | top_shap_signals |
| --- | --- | --- | --- | --- | --- | --- |
| TXN-0147293 | CUST-07061 | 2026-05-22 13:56:00 | 49.59 | 0.993762 | block | is_new_device=1.0 (+2.1890), geo_distance_from_home=160.17 (+1.8438), risk_segment=high (+0.8253) |
| TXN-0288343 | CUST-05783 | 2026-09-10 18:39:05 | 31.09 | 0.992881 | block | is_new_device=1.0 (+2.1856), geo_distance_from_home=234.7 (+1.8285), risk_segment=high (+0.8443) |
| TXN-0221786 | CUST-00057 | 2026-06-05 06:39:00 | 67.05 | 0.992875 | block | is_new_device=1.0 (+2.1650), geo_distance_from_home=287.03 (+1.8256), risk_segment=high (+0.8555) |
| TXN-0417769 | CUST-01726 | 2026-04-28 12:47:43 | 367.85 | 0.992698 | block | is_new_device=1.0 (+2.0009), geo_distance_from_home=354.41 (+1.8217), risk_segment=high (+0.8141) |
| TXN-0432087 | CUST-03840 | 2026-04-30 18:39:35 | 114.02 | 0.992657 | block | is_new_device=1.0 (+1.8947), geo_distance_from_home=152.47 (+1.8492), risk_segment=high (+0.8187) |
| TXN-0350980 | CUST-01654 | 2026-05-04 10:22:31 | 151.27 | 0.992622 | block | is_new_device=1.0 (+1.9912), geo_distance_from_home=139.8 (+1.8251), risk_segment=high (+0.8324) |
| TXN-0197951 | CUST-04108 | 2026-05-02 09:16:07 | 113.99 | 0.992559 | block | is_new_device=1.0 (+1.9989), geo_distance_from_home=240.13 (+1.8147), risk_segment=high (+0.8596) |
| TXN-0112255 | CUST-09364 | 2026-09-23 13:52:31 | 169.69 | 0.992497 | block | is_new_device=1.0 (+1.9395), geo_distance_from_home=332.91 (+1.8503), risk_segment=high (+0.8605) |
| TXN-0045116 | CUST-05980 | 2026-06-15 13:00:31 | 174.26 | 0.992264 | block | is_new_device=1.0 (+2.1576), geo_distance_from_home=144.98 (+1.7919), risk_segment=high (+0.8088) |
| TXN-0061730 | CUST-09391 | 2026-08-15 06:21:11 | 86.29 | 0.992225 | block | is_new_device=1.0 (+2.0339), geo_distance_from_home=141.62 (+1.8438), risk_segment=high (+0.8622) |

## Traced seeded-cohort transaction (used in all later steps)

Selection rule: cohort (amt_to_monthly_spend >= 0.5442, cross-border, new device), action = block, is_fraud = true, highest risk_score, tie-break txn_id.

| Field | Value |
| --- | --- |
| txn_id | **TXN-0234209** |
| customer_id | CUST-08669 |
| txn_ts | 2026-06-27 13:08:48 |
| amount | 323.96 |
| amt_to_monthly_spend | 0.7825 |
| is_cross_border / is_new_device | 1 / 1 |
| is_fraud | True |
| risk_score | 0.9844108757126732 |
| recommended_action | block |
| model_version | 1 |

top_shap_signals:

```json
[{"feature": "is_new_device", "value": 1.0, "shap": 2.5724}, {"feature": "geo_distance_from_home", "value": 450.63, "shap": 1.8741}, {"feature": "is_online", "value": 1.0, "shap": 1.2001}]
```

Seeded cohort across all rows: 3,145 txns, 38 blocked, mean risk_score 0.6101.

## Re-score via job run 379167641926204

The `batch_scoring` job task overwrote the table again: Delta version 4 (commit 2026-10-20 04:38:50 UTC), scored_at advanced from 2026-10-20 02:40:39 to **2026-10-20 04:38:02 UTC**, 464,632 rows, model_version 1. TXN-0234209 still scores 0.9844108757126732 / block.
