# Lakebase Write Path Evidence — Fraud Cases

**Date:** 2026-10-17  
**Workspace:** fevm-workshop-guy  
**Database:** `fe_bar_db`, schema `cases`

## Schema Definition

### cases.fraud_cases

| Column | Type | Constraints |
| --- | --- | --- |
| case_id | UUID | PRIMARY KEY, DEFAULT gen_random_uuid() |
| txn_id | TEXT | NOT NULL |
| status | TEXT | NOT NULL, DEFAULT 'open', CHECK in (open, in_review, closed) |
| assigned_queue | TEXT | NOT NULL, CHECK in (auto_block, analyst_review, auto_approve) |
| recommended_action | TEXT | NOT NULL, CHECK in (approve, review, block) |
| notes | TEXT | nullable |
| created_by | TEXT | NOT NULL |
| created_at | TIMESTAMPTZ | NOT NULL, DEFAULT now() |
| updated_at | TIMESTAMPTZ | NOT NULL, DEFAULT now() |

### cases.case_actions

| Column | Type | Constraints |
| --- | --- | --- |
| action_id | UUID | PRIMARY KEY, DEFAULT gen_random_uuid() |
| case_id | UUID | NOT NULL, FK to fraud_cases ON DELETE CASCADE |
| action_type | TEXT | NOT NULL, CHECK in (case_opened, recommendation, routed, analyst_decision, note, case_closed) |
| outcome | TEXT | nullable |
| actor | TEXT | NOT NULL |
| created_at | TIMESTAMPTZ | NOT NULL, DEFAULT now() |

### Indexes

* `idx_fraud_cases_txn_id` on fraud_cases(txn_id)
* `idx_fraud_cases_status_created` on fraud_cases(status, created_at)
* `idx_case_actions_case_created` on case_actions(case_id, created_at)
* `idx_fraud_cases_txn_open` UNIQUE on fraud_cases(txn_id) WHERE status <> 'closed' (prevents duplicate open cases)

## Validation Results

### Round-trip test

* Target transaction: TXN-0142590 (CUST-04866, amt_to_monthly_spend 87.78x, cross-border, geo_distance 597.56 km)
* Case created: `abda6590-c9a4-4df2-a9e4-9f2373d6e904`
* Persistence verified: close connection, reopen, read back — all fields match
* Audit trail: 4 actions (case_opened, recommendation, analyst_decision, case_closed)
* Idempotency: second create for same txn_id returns same case_id
* Rejections: invalid recommended_action (CheckViolation), invalid status (CheckViolation), non-existent txn_id (ValueError)

### Write Latency (50 create-and-read-back round trips, reused connection)

| Metric | Value |
| --- | --- |
| p50 | 33.21 ms |
| p95 | 42.40 ms |

### Unity Catalog Visibility

`fe_bar_lakebase.cases.fraud_cases` is queryable from serverless notebook compute via Spark SQL. 10 rows returned including validation_test cases.
