# Step 11: high-value triage (redact, don't filter)

Workspace fevm-workshop-guy. Step dated 2026-11-09 (US); work and checks ran 2026-11-10 UTC. Conversation 4443667514456316. Branch `step11/2026-11-09_fevm-workshop-guy_conv-4443667514456316` from main dc114b5. 100% synthetic data.

## Summary

| Item | Value |
| --- | --- |
| Goal | Make the 705 flagged transactions with amount > 10000 triageable without loosening governance |
| App deployment | `01f1dcc1df121891906c3a2c6df85a1a` (SUCCEEDED 2026-11-10 04:47:45 UTC), app RUNNING |
| Live-test case | `d2a1d4a1-7f84-4ed9-b9aa-4146c9f57592` (TXN-0189627), open, auto_block, created 2026-11-10 05:11:19 UTC, db_inserted_by `8f239f44-078a-4f8f-90f1-4c1b0bcdc26c` (App role), created_by `fraud_triage_copilot:agent` |
| Validation | `validation_notebooks/high_value_triage.ipynb`: B.9 24 PASS / 0 FAIL; B.10 follow-up 3 PASS / 0 FAIL (E.10c); E.8c observed, no text evidence |
| Genie | 13/13 PASS as pii (11 existing + 2 new) |
| Branch commit 1 | c57fad1 (code, views, exports, notebook, docs) |

## Run timestamps (UTC, 2026-11-10)

| What | When |
| --- | --- |
| Part A before state, read-only | 04:12:45 |
| App deployment SUCCEEDED | 04:47:45 |
| Dashboard draft update / published revision | 04:54:07 |
| Live-test case created (user click) | 05:11:19 |
| Validation run, B.0 to B.9 | started 05:20:49 |
| Re-run of B.7 to B.9 after the benchmark fix | about 05:47; Genie export `exported_at` 05:47:55 |
| B.10 follow-up, run alone (non_pii checks) | 23:27:24 |

The B.1 timestamp printed in B.9 is 05:20:49 because B.1 was not re-run with B.7 to B.9.

## Before vs after (UC as databricks_reader_17063 unless noted)

| Measure | Before (Part A) | After (Part E) |
| --- | --- | --- |
| triage_queue rows | 24,201 | 24,906 |
| triage_queue high-value rows | 0 | 705 (= Postgres as fraud_triage_agent: 705) |
| Non-null amount on high-value rows (triage_queue, case_summary) | n/a | 0, 0 |
| Non-null SHAP value for amount / amt_to_cust_avg_30d / amt_to_monthly_spend on high-value rows | n/a | 0 (1,688 signals keep feature name and shap) |
| case_summary rows | 222 | 229 |
| case_summary high-value cases | 0 | 7 |
| TXN-0189627 in triage_queue | absent | rank 231, amount NULL, over_10k, block, case open |
| baseline_comparison | model $7,010,482.03 vs rule $933,889.13 caught | identical |
| exposure | 6 cells | identical, total $88,304,104.56 |
| fraud_analyst (Postgres RLS) | high-value cases hidden | 211 cases visible, 0 of 7 high-value |
| Reader role_table_grants | 19 rows | 19 rows, 0 added, 0 removed; no memberships |
| View latency through UC | n/a | triage_queue 2.8 s, case_summary 3.2 s |
| App: find a high-value txn | not reachable (top 50 queue, top 200 picker, best rank 231) | exact txn_id search and "High-value only" filter in SQL |

case_summary 222 to 229: 6 existing high-value cases (TXN-0142590 x4, TXN-0256919, TXN-0068738, all closed) are now included, plus the live-test case.

## SQL diff summary (lakebase_dashboard.sql, same block in lakebase_fgac.sql)

* `case_summary` and `triage_queue` only. `exposure`, `baseline_comparison`, `score_distribution` and `case_actions_daily` still filter `amount <= 10000`; `model_thresholds` is unchanged.
* `amount` becomes `CASE WHEN tf.amount > 10000 THEN NULL ELSE tf.amount END`; new columns `is_high_value` and `amount_band` ('over_10k' / 'under_10k').
* `case_summary`: JOIN LATERAL probe kept, `ON tf.amount <= 10000` became `ON true`.
* `triage_queue.top_shap_signals`: on high-value rows the regexp also nulls the values of `amount` and `amt_to_cust_avg_30d`; `amt_to_monthly_spend` stays nulled on all rows.
* Both views read `fraud.txn_features` / `fraud.txn_risk_current` instead of `fraud_gov.*`. The `fraud_gov` row rule tests `pg_has_role(current_user, 'fraud_pii')`, and inside a view `current_user` is the caller (the UC reader), so through `fraud_gov` the views would still return 0 high-value rows (probe in Part A: 751 hidden). Approved option: `GRANT SELECT ON fraud.txn_features, fraud.txn_risk_current TO fraud_lead` (fraud_lead is already a fraud_pii member). Owner fraud_lead and security_barrier kept; no reader grant, RLS policy, membership or UC object changed.

## App (app/app.py only)

Exact txn_id lookup (parameterized query on `fraud_gov.txn_risk_current` with the case join); "High-value only (amount > $10,000)" checkbox joining `fraud_gov.txn_features` in SQL; action, queue and case-status filters in SQL; amount, High value and rank columns; txn_id box on Transaction Detail. `fraud_triage_agent.py`, `lakebase_cases.py`, `app.yaml` and the App role unchanged.

Live test (user clicked, notebook checked the database):

| Check | Result |
| --- | --- |
| Search TXN-0189627 | found: $14,581.03, block, rank 231 |
| Explain | returned an explanation (user-observed) |
| Open case | 1 case, d2a1d4a1-7f84-4ed9-b9aa-4146c9f57592, db_inserted_by = App role |
| Second click | no duplicate, same case ID shown |
| Search TXN-0142590 | found at rank 3,933 |
| High-value only | 50 rows, min amount $10,161.53, first TXN-0189627 |

## Genie and dashboard

Genie space 01f1d7b464d510b9aa6cde48300787ca: text instruction and description now say the triage queue and case list include high-value rows with the amount redacted and dollar totals still exclude them; column configs for `amount`, `is_high_value`, `amount_band`. Two benchmarks added: "How many high-value transactions are in the triage queue?" (705) and "Show the top 5 high-value block transactions in the triage queue with their amount band" (TXN-0189627 first, then TXN-0193357, TXN-0371350, TXN-0291011, TXN-0448721).

The second question differs from the prompt ("...top 5 high-value block-band transactions in the triage queue"). Run 1: Genie left out `amount_band`, FAIL. Run 2 (reworded, approved): right rows, but `case_status` sometimes missing, FAIL. Run 3: `case_status` removed from the expected SQL (approved), PASS.

No existing benchmark question or expected SQL changed (diff of the 11 existing benchmarks, origin/main vs branch: 0 changed). Their results move with the data:

| Benchmark | Part A | After | Why |
| --- | --- | --- | --- |
| Which case queue has the most cases with a block recommendation? | auto_block 11 | auto_block 16 | +5 high-value auto_block/block cases now in case_summary (TXN-0142590 x4, TXN-0189627) |
| Cases per day and queue, week of 2026-10-19 | 10-21 auto_block 7; 10-23 auto_block 3 | 8; 4 | one TXN-0142590 case on each day now included |
| Top 5 customers by flagged triage_queue txns | ..., CUST-06862 16 | CUST-00358 17 enters; CUST-06862 (16) drops out | CUST-00358 has 3 high-value flagged rows (14 before); CUST-06862 ties at 16 with CUST-03895 and CUST-04867 and is cut by LIMIT 5 |
| How many open cases are in each queue? | auto_block 10 | auto_block 11 | live-test case (open) |
| Why was TXN-0234209 flagged? | block, 0.98441 | unchanged | |

Dashboard 01f1ce7f835a1e81b05ebb664bf0994c: `filter_high_value` on the triage table, counter "High-value flagged (amount redacted)" = 705, `is_high_value` and `amount_band` columns, Case KPIs caption says high-value cases are included. Published with embedded credentials; all 11 datasets load. Both JSON files re-exported from the live objects (genie 30,132 chars, dashboard 56,831 chars).

## Deferred and corrections

* Follow-up 2026-11-10 22:26 UTC (branch `step11b/2026-11-10_fevm-workshop-guy_conv-4443667514456316`): E.10c done by a second non_pii test user (user ID 76510230734315), 11/11 PASS of 11 asked, both new benchmarks pass; 2 not asked, accepted by the user (`genie_agent_benchmark_evidence_logs/non_pii_test_user_2026-11-10.md`). Before grading, `risk_score` was dropped from the top-5 benchmark's expected SQL (approved); Genie space re-exported. E.8c: that user was denied at the App URL (observed by the tester, reported by the user); no text evidence, because the audit log shows only the sign-ins and screenshots are not accepted, so not counted as PASS.
* App ACL: `pii` CAN_USE was added at 03:48:15 UTC, before Part A (`logs/app_permissions_2026-11-09.md`).
* Commit c57fad1's message says "3 expected answers changed (approved)". That is wrong: no existing benchmark changed; only the 4 results above moved. Not rewritten; corrected here.
* 2026-11-10 (branch `step11d/2026-11-10_fevm-workshop-guy_conv-4443667514456316`): `prompts/` (14 files, including `step11_4443667514456316.md`) and `docs/PROMPTS.md` removed from the repo by the user's decision; conversation IDs in `docs/CONVERSATION_IDS.md` are the build evidence. The files remain in git history up to commit 8271694.
