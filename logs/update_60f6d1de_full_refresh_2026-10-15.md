# Pipeline Run Evidence — Full Refresh

**Update ID:** `60f6d1de-d62b-4deb-9701-0455c5c748ea`  
**Pipeline:** FE BAR Bronze Silver AutoLoader Pipeline  
**Pipeline ID:** `c0db28b8-dbd2-432d-99cf-4ea2aea60274`  
**State:** COMPLETED  
**Type:** Full Refresh  
**Start:** 2026-10-15T03:29:06.297Z  
**End:** 2026-10-15T03:29:51.499Z  
**Duration:** ~45 seconds  
**Cluster:** `1015-031836-h0c83uzm-v2n`  
**Genie Conversation ID:** 2172058462486781  
**Workspace:** fevm-workshop-guy  
**Date:** 2026-10-15  

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
| `dim_customer_bronze` | STREAMING_TABLE | COMPLETED | 10,768 | — |
| `dim_merchant_bronze` | STREAMING_TABLE | COMPLETED | 5,402 | — |
| `fact_transactions_bronze` | STREAMING_TABLE | COMPLETED | 537,505 | — |
| `fact_prior_fraud_cases_bronze` | STREAMING_TABLE | COMPLETED | 53,788 | — |
| `dim_customer_silver` | MATERIALIZED_VIEW | COMPLETED | 9,289 | 1 |
| `dim_merchant_silver` | MATERIALIZED_VIEW | COMPLETED | 4,666 | 1 |
| `fact_transactions_silver` | MATERIALIZED_VIEW | COMPLETED | 464,679 | 17,932 |
| `fact_prior_fraud_cases_silver` | MATERIALIZED_VIEW | COMPLETED | 46,417 | 1,755 |

**Total rows ingested (bronze):** 607,463  
**Total rows materialized (silver):** 525,051  
**Total rows dropped by expectations:** 19,689  

## FGAC Policies Active

- **Row filter:** `filter_high_amount_txns` on `fact_transactions_silver` (hides amount > $10,000 from non-PII users)
- **Column mask:** `mask_avg_monthly_spend` on `dim_customer_silver` (PII group sees real values)

## Event Timeline

| Time (UTC) | Flow | Event |
| --- | --- | --- |
| 03:29:29.888 | fact_prior_fraud_cases_silver | QUEUED |
| 03:29:29.889 | dim_merchant_silver | QUEUED |
| 03:29:29.890 | dim_merchant_bronze | QUEUED |
| 03:29:30.083 | fact_prior_fraud_cases_bronze | STARTING |
| 03:29:31.285 | fact_prior_fraud_cases_bronze | RUNNING |
| 03:29:31.842 | fact_transactions_bronze | STARTING |
| 03:29:32.425 | fact_transactions_bronze | RUNNING |
| 03:29:32.594 | dim_merchant_bronze | STARTING |
| 03:29:33.171 | dim_merchant_bronze | RUNNING |
| 03:29:33.331 | dim_customer_bronze | STARTING |
| 03:29:33.948 | dim_customer_bronze | RUNNING |
| 03:29:39.644 | fact_prior_fraud_cases_bronze | COMPLETED (streaming update) |
| 03:29:39.732 | dim_merchant_bronze | COMPLETED (streaming update) |
| 03:29:39.740 | fact_prior_fraud_cases_bronze | COMPLETED |
| 03:29:39.747 | dim_merchant_bronze | COMPLETED |
| 03:29:39.787 | dim_customer_bronze | COMPLETED (streaming update) |
| 03:29:39.869 | dim_customer_bronze | COMPLETED |
| 03:29:41.001 | dim_merchant_silver | PLANNING |
| 03:29:41.003 | dim_customer_silver | PLANNING |
| 03:29:41.004 | fact_prior_fraud_cases_silver | PLANNING |
| 03:29:41.962 | fact_transactions_bronze | COMPLETED (streaming update) |
| 03:29:42.108 | fact_transactions_bronze | COMPLETED |
| 03:29:42.541 | fact_prior_fraud_cases_silver | STARTING |
| 03:29:42.554 | dim_customer_silver | STARTING |
| 03:29:42.558 | dim_merchant_silver | STARTING |
| 03:29:42.655 | dim_merchant_silver | RUNNING |
| 03:29:42.657 | fact_prior_fraud_cases_silver | RUNNING |
| 03:29:42.660 | dim_customer_silver | RUNNING |
| 03:29:44.585 | fact_transactions_silver | PLANNING |
| 03:29:45.138 | fact_transactions_silver | STARTING |
| 03:29:45.199 | fact_transactions_silver | RUNNING |
| 03:29:46.942 | dim_merchant_silver | COMPLETED |
| 03:29:47.003 | dim_customer_silver | COMPLETED |
| 03:29:47.006 | fact_prior_fraud_cases_silver | COMPLETED |
| 03:29:50.577 | fact_transactions_silver | COMPLETED |
| 03:29:50.607 | — | Update 60f6d1 COMPLETED |

## Source

Notebook: `/Workspace/Users/alex.owen@databricks.com/FE-BAR-2026-repo/pipeline_code_and_build_evidence`
