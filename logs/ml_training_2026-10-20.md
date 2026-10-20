# ML Training Evidence — fraud_risk_model (Layer 3)

**Date:** 2026-10-20  
**Workspace:** fevm-workshop-guy  
**Notebook:** `fraud_model_training.ipynb` (serverless)  
**MLflow experiment:** `/Users/alex.owen@databricks.com/fe_bar_fraud_risk_model` (ID 2565515039400057)  
**MLflow run ID:** `d89beaca8f81447780da60ed2ea7c811`  
**Registered model:** `workshop_guy_catalog.fe_bar_a0.fraud_risk_model` **version 1**, alias **`champion`** → v1

## Pre-flight governance check (Part A)

| Check | Value |
| --- | --- |
| current_user() | alex.owen@databricks.com |
| is_account_group_member('pii') | True |
| txn_features_gold rows | 464,632 |
| rows with amount > 10000 | 751 |
| non-null amt_to_monthly_spend | 431,471 |
| Result | PASSED (high-amount rows visible, spend ratio unmasked) |

## Data split (time-based, not random)

Cutoff timestamp: **2026-09-21 15:20:18** (test = txn_ts >= cutoff)

| Split | Rows | Fraud rows | Fraud prevalence |
| --- | --- | --- | --- |
| train | 371,705 | 8,796 | 2.37% |
| test | 92,927 | 1,735 | 1.87% |
| all | 464,632 | 10,531 | 2.27% |

## Model

* LightGBM binary classifier (300 trees, num_leaves 15, max_depth 5, lr 0.05, subsample 0.8, colsample 0.8), wrapped in a custom MLflow pyfunc that fixes category levels for `risk_tier`, `risk_segment`, `mcc_category`
* Class imbalance: **scale_pos_weight = 362,909 / 8,796 = 41.2584**
* 16 features; excluded is_fraud, txn_id, customer_id, merchant_id, device_id, txn_ts, home_country, merchant_country, channel
* Input signature (all optional; numerics double, categoricals string) and input example logged
* Registered vs in-memory score check: max |diff| on 2,000 test rows = 0.0

## Test-set metrics

| Metric | Value |
| --- | --- |
| ROC-AUC | 0.8448 |
| PR-AUC | 0.2808 |
| Precision@100 | 0.7800 |
| Precision@500 | 0.4080 |
| Recall@500 | 0.1176 |
| Test fraud prevalence (baseline) | 0.0187 |
| Overall fraud prevalence | 0.0227 |

PR-AUC is 15.0x the prevalence baseline.

## Seeded cohort lift (test set)

Cohort = amt_to_monthly_spend >= train p90 (**0.5442**) AND is_cross_border = 1 AND is_new_device = 1.

| Measure | Value |
| --- | --- |
| Cohort rows (test) | 116 |
| Cohort fraud rate | 18.10% |
| Overall fraud rate | 1.87% |
| Fraud lift | 9.70x |
| Mean risk_score, cohort | 0.8756 |
| Mean risk_score, non-cohort | 0.2145 |
| Share of top 500 scored txns in cohort | 1.0% |
| PR-AUC on non-cohort rows | 0.2809 (prevalence 0.0185) |

The top-500 share is only 1% and non-cohort PR-AUC (0.2809) matches overall PR-AUC, so the model learned signal beyond the seeded rule.

## Thresholds for recommended_action (logged as MLflow params)

| Param | Value | Rule |
| --- | --- | --- |
| block_threshold | 0.950267 | lowest score where test precision >= 0.50 |
| review_threshold | 0.871416 | highest score where cumulative test recall >= 0.60 |
| approve | < 0.871416 | |

| Band | Txns | % volume | Fraud in band | Precision | Recall |
| --- | --- | --- | --- | --- | --- |
| block | 288 | 0.31% | 144 | 0.5000 | 0.0830 |
| review | 3,567 | 3.84% | 897 | 0.2515 | 0.5170 |
| approve | 89,072 | 95.85% | 694 | 0.0078 | 0.4000 |

block + review combined: precision 0.2700, recall 0.6000, 3,855 txns (4.15% of test volume). Scores are uncalibrated (scale_pos_weight inflates them), so thresholds sit high in [0, 1].

## Mean absolute SHAP (log-odds, 20,000-row random test sample)

| Feature | Mean abs SHAP |
| --- | --- |
| geo_distance_from_home | 0.2560 |
| risk_tier | 0.1859 |
| risk_segment | 0.1721 |
| amt_to_monthly_spend | 0.1675 |
| amount | 0.1342 |
| is_new_device | 0.1335 |
| is_cross_border | 0.1011 |
| is_online | 0.0925 |
| mcc_category | 0.0516 |
| secs_since_prev_txn | 0.0423 |
| amt_to_cust_avg_30d | 0.0417 |
| tenure | 0.0394 |
| hour_of_day | 0.0269 |
| txn_count_24h | 0.0053 |
| txn_count_1h | 0.0007 |
| is_night | 0.0000 |

Artifacts: `shap/shap_summary.png`, `shap/mean_abs_shap.csv`, `thresholds/threshold_bands.csv`.
