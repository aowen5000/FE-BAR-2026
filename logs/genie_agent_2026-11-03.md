# Step 8: Genie Agent "FE Bar Fraud Risk Ops" (2026-11-03)

Workspace fevm-workshop-guy. Genie Code conversation 2326365276521178. Branch `step8/2026-11-03_fevm-workshop-guy_conv-2326365276521178` from main `549fac2016d2ed4f976426a7ec95c5e4025728fa`. Evidence notebook: `validation_notebooks/genie_agent_validation.ipynb`, committed with outputs. Space definition: `genie/fraud_risk_ops_genie.json`.

## Space

| Field | Value |
| --- | --- |
| Name | FE Bar Fraud Risk Ops |
| Space ID | `01f1d7b464d510b9aa6cde48300787ca` |
| URL | https://fevm-workshop-guy.cloud.databricks.com/genie/rooms/01f1d7b464d510b9aa6cde48300787ca |
| Warehouse | `9bbc027402111984` (Serverless Starter Warehouse) |
| Folder | `/Users/alex.owen@databricks.com/FE Bar Genie` |
| Description | For the Head of Fraud Risk Ops at a regional card issuer. Answers questions about fraud model performance vs the baseline rule, fraud dollars caught and missed, false positives, block-band precision and score calibration, the triage queue and why a transaction was flagged (risk score, recommended action, top SHAP signals), and case workload by queue, status and date. Data is synthetic; dollar figures exclude transactions over $10,000 (governed fraud_dash views). |
| Permissions | alex.owen@databricks.com CAN_MANAGE (inherited), admins CAN_MANAGE (inherited). No CAN_RUN or other grants added in this step. |

## Pre-flight (Part A)

* `current_user()` = alex.owen@databricks.com; `is_account_group_member('pii')` = true. All Genie answers below were therefore produced as a pii user.
* Git folder was on `main`, clean, `main` = `origin/main` = `549fac2016d2ed4f976426a7ec95c5e4025728fa`.
* Notebook output baseline on origin/main: 12 notebooks, every one with 0 errors (table in notebook cell A.2).
* Warehouse `9bbc027402111984` ran `SELECT * ... LIMIT 1` on all 8 candidate sources and the 3 extra fraud_dash views (all SUCCEEDED).

## Governance findings and decisions

Check: would a non-pii user see transactions with amount > 10000, or unmasked `amt_to_monthly_spend` / `avg_monthly_spend`? Context: UC grants give `account users` ALL PRIVILEGES on `workshop_guy_catalog`. On `fe_bar_lakebase`, `account users` has READ METADATA only.

| Source | Rows | Row filter / mask | amount > 10000 | Unmasked amt_to_monthly_spend | Decision |
| --- | --- | --- | --- | --- | --- |
| fe_bar_a0.scored_transactions | 464,632 | none | 751 | 148,479 rows (inside `top_shap_signals` JSON) | EXPOSED, not attached |
| fe_bar_a0.txn_features_gold | 464,632 | none | 751 | 431,471 rows (column) | EXPOSED, not attached |
| fe_bar_a0.customer_risk_profile_gold | 9,289 | none | n/a | n/a | Indirect (`avg_amount_30d` averages unfiltered txns), not attached |
| fe_bar_a0.risk_score_calibration | 12 | none | n/a (counts only) | n/a | Attached |
| fe_bar_a0.dim_merchant_silver | 4,666 | none | n/a | n/a | Safe, but no join key to any governed source, not attached |
| fraud_dash.case_summary | 221 | view filters amount <= 10000 | 0 | n/a | Attached |
| fraud_dash.exposure | 6 | view filters amount <= 10000 | n/a | n/a | Attached |
| fraud_dash.baseline_comparison | 2 | view filters amount <= 10000 (463,881 rows evaluated) | n/a | n/a | Attached |
| fraud_dash.triage_queue | 24,201 | view filters amount <= 10000 | 0 | 5,952 rows before the fix, 0 after | Attached after the view fix below |
| fraud_dash.score_distribution | 31 | counts only | n/a | n/a | Attached |
| fraud_dash.case_actions_daily | 8 | counts only | n/a | n/a | Attached |

Decisions (all by the user in conversation 2326365276521178):

1. Option 1, governed sources only. `scored_transactions` and `txn_features_gold` are not attached. Their exposure to non-pii users through the `account users` catalog grant is an upstream governance gap and is NOT fixed in this step.
2. Option 4, fix the view. During Part C, before the space was created, `fraud_dash.triage_queue.top_shap_signals` was found to carry the numeric value of the `amt_to_monthly_spend` feature in 5,952 rows. With `amount` in the same view, that reveals the masked `dim_customer_silver.avg_monthly_spend` (amount / value). With the user's approval, the Postgres view was replaced (`CREATE OR REPLACE VIEW`, run as owner `fraud_lead`) with `regexp_replace(r.top_shap_signals, '("feature": "amt_to_monthly_spend", "value": )[^,}]+', '\1null', 'g')`. Nothing else in the view changed.
   * Verified after the change: owner `fraud_lead`, `security_barrier=true` and the ACL (including `databricks_reader_17063=r`) are unchanged. There are 24,201 rows, 0 with a numeric `amt_to_monthly_spend` value and 6,337 with `"value": null`. TXN-0234209's signals are unchanged.
   * Source of truth updated in the same commit: `lakebase_fgac.sql` and `lakebase_dashboard.sql`.
   * Not changed: grants, roles, policies, RLS, the `fraud_gov` views, synced tables, gold/silver tables. The published dashboard reads this view and now shows `null` for that one feature value.

## Design (Part B, approved)

| Surface | Content |
| --- | --- |
| Data sources (7) | fraud_dash `triage_queue` (flagged txns, risk score, action, SHAP signals, case/queue: why flagged, rankings); `case_summary` (one row per case: status, queue, created_at: open cases, time windows); `case_actions_daily` (opened/closed per day: time windows); `exposure` (action x is_fraud counts and $: caught/missed/false positives); `baseline_comparison` (model vs rule `is_cross_border = 1 AND is_new_device = 1`); `score_distribution` (score histogram with thresholds); fe_bar_a0 `risk_score_calibration` (observed precision per band) |
| Column descriptions | risk_score (champion v1, run d89beaca..., uncalibrated), recommended_action (block >= 0.950267, review >= 0.871416, else approve), top_shap_signals (top-3 {feature, value, shap} in log-odds; amt_to_monthly_spend value always null), is_fraud (synthetic label), assigned_queue (auto_block / analyst_review / 'no case'), status / case_status, risk_rank, bucket, confidence, observed_precision, strategy, created_at / action_date date roles |
| Hidden | risk_score_calibration.model_run_id, split_cutoff_ts, computed_at; score_distribution.model_run_id |
| Entity matching + format assistance | recommended_action (4 tables), assigned_queue (2), status, case_status, strategy, action_type, band, bucket, confidence. Never on IDs, amounts or scores. mcc_category / risk_tier / channel are not in any governed source. |
| Join spec | `case_summary.txn_id = triage_queue.txn_id`, MANY_TO_ONE (221 cases on 215 txns; 21 matching rows) |
| SQL measures | Fraud $ caught (exposure: is_fraud and action in block/review) = 7,010,482.03; Fraud $ missed (is_fraud and approve) = 975,725.89; False positives (not is_fraud and block/review, count) = 17,630; Block-band precision = 0.5 |
| SQL filters / expressions | Open cases (`case_summary.status = 'open'`, 9 rows); Flagged by model (`triage_queue.recommended_action IN ('block','review')`, 24,201); Top SHAP signal (`get_json_object(triage_queue.top_shap_signals, '$[0].feature')`) |
| Example SQL (4, all run read-only) | Share of fraud dollars caught per strategy (model 0.8778, baseline 0.1169); top 10 review txns without a case; cases opened/closed per week; open cases with top signal and calibration band (range join, 9 rows) |
| Sample questions (5) | How does the model compare to the baseline rule on fraud dollars caught? / Which open cases are in the auto_block queue? / What are the 10 highest-risk transactions without a case? / How many cases were opened and closed each week? / What is the observed fraud rate in each risk score band? |
| Text instruction (695 chars) | PURPOSE (synthetic data, audience); DATA QUALITY NOTES (is_fraud synthetic; fraud_dash $ exclude amount > 10000); CONSTRAINTS (merchant category, risk tier, channel, customer spend not available, do not estimate); summary rule (state the $10,000 exclusion) |
| Benchmarks | 11 (the 10 requested plus "Which case queue has the most cases with a block recommendation?"); 2 are refusal/caveat questions with an evaluation note and no SQL |

## Benchmarks (Conversation API, final round = round 1)

Each question was asked in a new Genie conversation from the notebook. PASS = COMPLETED and every expected value present in the result (values: numbers within 0.01; strings as substrings), or, for refusal questions, no result rows and an explicit "not available" answer.

| # | Question | Genie SQL (round 1) | Expected | Round 0 | Round 1 |
| --- | --- | --- | --- | --- | --- |
| 1 | How much fraud did the model catch vs the baseline rule? | `SELECT strategy, rule_text, fraud_amount_caught, fraud_caught_count, total_fraud_amount FROM fe_bar_lakebase.fraud_dash.baseline_comparison WHERE strategy IS NOT NULL AND fraud_amount_caught IS NOT NULL ORDER BY fraud_amount_caught DESC` | model $7,010,482.03 (6,571), baseline $933,889.13 (2,767) | PASS | PASS |
| 2 | What is the block-band precision? | `SELECT MAX(CASE WHEN bucket = 'block_band' THEN observed_precision END) AS block_band_precision FROM workshop_guy_catalog.fe_bar_a0.risk_score_calibration` | 0.5 (matches logs/ml_training_2026-10-20.md: block 288 txns, 144 fraud, 0.5000) | PASS | PASS |
| 3 | Why was TXN-0234209 flagged? | `WITH target_txn AS (SELECT txn_id, recommended_action, risk_score, top_shap_signals, case_status, assigned_queue FROM fe_bar_lakebase.fraud_dash.triage_queue WHERE txn_id = 'TXN-0234209' ...) SELECT txn_id, recommended_action, ROUND(risk_score, 5), case_status, assigned_queue, get_json_object(top_shap_signals, '$[0].feature') ... '$[2].shap' FROM target_txn` | 0.98441, block, is_new_device +2.5724, geo_distance_from_home +1.8741, is_online +1.2001 (open, auto_block) | PASS | PASS |
| 4 | Which merchant categories have the most block recommendations? | none (text: "Merchant category is not available in this schema...") | refusal / caveat | PASS | PASS |
| 5 | How many open cases are in each queue? | `SELECT assigned_queue, COUNT(*) AS open_case_count FROM fe_bar_lakebase.fraud_dash.case_summary WHERE status = 'open' AND assigned_queue IS NOT NULL GROUP BY assigned_queue ORDER BY open_case_count DESC, assigned_queue` | auto_block 9 (matches case_summary) | PASS | PASS |
| 6 | How many cases were opened between October 20 and October 23, 2026? | `SELECT SUM(action_count) AS cases_opened FROM fe_bar_lakebase.fraud_dash.case_actions_daily WHERE action_type = 'case_opened' AND action_date BETWEEN DATE '2026-10-20' AND DATE '2026-10-23'` | 121 | PASS | PASS |
| 7 | How many cases were created per day and queue in the week starting October 19, 2026? | `SELECT DATE_TRUNC('DAY', created_at) AS created_day, assigned_queue, COUNT(DISTINCT case_id) AS cases_created FROM fe_bar_lakebase.fraud_dash.case_summary WHERE ... created_at >= TIMESTAMP '2026-10-19 00:00:00' AND created_at < TIMESTAMP '2026-10-26 00:00:00' GROUP BY ... ORDER BY created_day, assigned_queue` | 5 rows: 10-20 analyst_review 1; 10-21 analyst_review 56, auto_block 7; 10-23 analyst_review 54, auto_block 3 | PASS | PASS |
| 8 | Which 5 customers have the most flagged transactions in the triage queue? | `WITH customer_flagged_counts AS (SELECT customer_id, COUNT(*) ... FROM fe_bar_lakebase.fraud_dash.triage_queue WHERE recommended_action IN ('block','review') ... GROUP BY customer_id), ranked_customers AS (... RANK() OVER (ORDER BY flagged_txn_count DESC, customer_id ASC)) SELECT ... WHERE customer_rank <= 5` | CUST-01399 20, CUST-00167 17, CUST-03895 / CUST-04867 / CUST-06862 16 | PASS | PASS |
| 9 | What is the average monthly spend for customer CUST-08669? | none (text: "That data is not available in this schema...") | refusal | PASS | PASS |
| 10 | How many fraud dollars did the model miss, and how many false positives did it generate? | `SELECT fraud_amount_missed, false_positive_count FROM fe_bar_lakebase.fraud_dash.baseline_comparison WHERE strategy = 'model'` | $975,725.89; 17,630 | PASS | PASS |
| 11 | Which case queue has the most cases with a block recommendation? | `WITH queue_counts AS (SELECT assigned_queue, COUNT(*) AS case_count FROM fe_bar_lakebase.fraud_dash.case_summary WHERE recommended_action = 'block' AND assigned_queue IS NOT NULL GROUP BY assigned_queue), ranked_queues AS (... RANK() ...) SELECT ... WHERE rnk <= 1` | auto_block 10 | PASS | PASS |

Total: round 0 = 11/11 PASS, round 1 = 11/11 PASS. The full generated SQL, Genie's text, the first result rows and the conversation/message IDs for both rounds are in the notebook outputs (cells C.4 and C.5).

## Native benchmark eval API (genie_create_eval_run)

Available in this workspace.

| Round | Eval run | GOOD | NEEDS_REVIEW | BAD |
| --- | --- | --- | --- | --- |
| 0 (as created) | `01f1d7b5056e1fa38671eb2ea42bf088` | 6/11 | 2 (#4, #9) | 3 (#1, #2, #7) |
| 1 (benchmark repair) | `01f1d7bb45e618c59ba0c9cd95847221` | 8/11 | 2 (#4, #9) | 1 (#3) |

## Tuning rounds

* **Round 0:** as approved. Conversation API 11/11. Native scorer BAD on #1, #2 and #7. Every one had correct numbers but a different result shape from the expected SQL: #1 and #2 expected extra count columns; #7 expected a DATE, and Genie returned a DAY-truncated timestamp.
* **Round 1:** benchmark repair only, following the skill's repair stack (invalid expected SQL is a benchmark fix, not a Genie tuning target). The expected SQL for #1, #2 and #7 was aligned to the question's shape and re-verified on the warehouse. No Genie descriptions, joins, snippets, examples or text changed. Result: Conversation API 11/11; native eval 6 to 8 GOOD.
* No round 2: nothing failed under the Conversation API grading, and the remaining native items are not Genie errors (see below).

## Still failing or open

* **Native #3, "Why was TXN-0234209 flagged?":** BAD on result shape only. Genie sometimes parses `top_shap_signals` into 9 columns (feature/value/shap x 3) and sometimes returns the raw JSON column; the values are correct either way (Conversation API PASS in both rounds). One round-1 answer took 522 s, against 14 to 34 s for the others.
* **Native #4 and #9 (refusal questions):** NEEDS_REVIEW by design. They have no canonical SQL, and Genie answered "not available" both times.
* **Upstream governance gap (not fixed, flagged):** `scored_transactions` (751 txns > 10000; `amt_to_monthly_spend` values in `top_shap_signals`) and `txn_features_gold` (751 txns > 10000; `amt_to_monthly_spend` column) have no row filter or mask, and `account users` has ALL PRIVILEGES on `workshop_guy_catalog`. `customer_risk_profile_gold.avg_amount_30d` averages unfiltered transactions.
* **Access:** non-pii users currently have no SELECT on `fe_bar_lakebase`, so the space only works for its owner until access is granted in a later step. No CAN_RUN was granted.
* All benchmark answers were produced as a pii user (Genie runs queries as the asking user).
