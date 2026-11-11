# Step 12: evidence refresh (docs only)

Workspace fevm-workshop-guy. 2026-11-10 UTC. Conversation 513394016637772. Branch `step12/2026-11-10_fevm-workshop-guy_conv-513394016637772` from main 1677b8f (Step 11e merge; main had moved past 6183fbd, user approved 1677b8f as base). No SQL, App, notebook, pipeline, Genie space, dashboard, job, model or permission change; no notebook or job run. 100% synthetic data.

## Character counts

| File | Before (1677b8f) | After |
| --- | --- | --- |
| README.md | 8,242 | 8,886 |
| EVIDENCE.md | 7,199 | 11,914 |
| DECISIONS.md | 7,901 | 8,033 |
| BUILD.md | 8,954 | 8,954 (unchanged: a Step 12 row does not fit in 9,000) |

EVIDENCE.md limit: raised from 9,000 to 12,000 by the user, with option "small trims only". README, DECISIONS and BUILD stay at 9,000.

## EVIDENCE.md blocks

Added:
* Business value (first): B.4b-3 headline rows in both scopes, B.3b agent latency row, Step 11 "triage_queue high-value rows 0 to 705" row (user chose the Step 11 log row over the README KPI row), and the line "Analyst minutes per case are planning assumptions, not measurements."
* Unity Catalog: 3 rows from gold_governance "Changes", the final_verification row filter line, the pointer line to the real non_pii test.
* Lakebase: the LIMITATIONS.md fraud_lead line (since Step 11).
* ML and Gen AI: batch scoring block (thresholds, consistency check 0.0, recommended_action distribution, top-1 row with top_shap_signals).
* Genie Agent: 13/13 as pii (Step 11), second non_pii run 11/11 of 11 asked.
* AI/BI dashboard (inside Databricks App): job run 659281894932228 SUCCESS, dashboard ID, 10 datasets, live-read proof, Step 11 republish line (all 11 datasets load).
* High-value triage: App ACL lines, E.8b PASS, non_pii App URL quoted as "denied, no text evidence" (not PASS), "Search TXN-0189627" and "High-value only" rows.

Changed:
* Lakebase deny table: `fraud_lead | direct SELECT ...` replaced by `fraud_analyst | direct SELECT fraud.txn_features | permission denied for table txn_features` (same section of logs/lakebase_fgac_2026-10-21.md).
* Databricks App: the two blocks merged into one.
* Intro sentence shortened.

Removed:
* UC: "Non-pii view, computed from the filter's non-pii branch ... not tested as a real non-pii identity."
* UC 29/29 block: the `fe_bar_a0` USE SCHEMA line and the owner-identity line.

## Cut list

| Cut | Why |
| --- | --- |
| Lakeflow: `dim_customer_silver` and `dim_merchant_silver` rows | Trim order step 1 |
| App Part D: db_inserted_by, Genie numbers and D.6 rows (kept: one case after repeat clicks; case visible in UC with no sync) | Trim order step 2 |
| App: two blocks merged into one | Trim order step 3 |
| Lakebase: p99 latency row | Small trim (user approved) |
| ML: block and review threshold-band rows from ml_training (thresholds still shown in the scoring block) | Small trim (user approved) |
| Job run: "Postgres fe_bar_db fraud.txn_risk_current" and "All equal" rows | Small trim (user approved) |
| Intro sentence | Small trim (user approved) |

No run, trace, case or conversation ID was dropped; no stage was dropped.

## Second non_pii run: Genie conversation IDs

Not in a committed file before this step; read 2026-11-10 from the Genie API (`GET /api/2.0/genie/spaces/01f1d7b464d510b9aa6cde48300787ca/conversations?include_all=true`) as space owner. Message 01f1dd4f81aa176b8882dc78d44eb40f was confirmed in conversation 01f1dd4f81751476806ff924ef6934bb with user_id 76510230734315.

| # | Conversation ID | Title |
| --- | --- | --- |
| 1 | 01f1dd4f81751476806ff924ef6934bb | How many high-value transactions are in the triage queue? |
| 2 | 01f1dd5004011f189948f68bda02298f | Show the top 5 high-value block transactions in the triage queue with their amount band |
| 3 | 01f1dd50265f1a039588eb8e11f3c65c | How many cases were created per day and queue in the week starting October 19, 2026? |
| 4 | 01f1dd504fc216019a6bb9eac4d9e918 | How many cases were opened between October 20 and October 23, 2026? |
| 5 | 01f1dd50dbe01635906c99b48ae6e4f5 | How many fraud dollars did the model miss, and how many false positives did it generate? |
| 6 | 01f1dd5180e8142abb8d85ded26ba939 | How many open cases are in each queue? |
| 7 | 01f1dd51976a18b1a889e4bd03c7dd8e | What is the average monthly spend for customer CUST-08669? |
| 8 | 01f1dd51e3d11e13b783b20b6e626505 | Which 5 customers have the most flagged transactions in the triage queue? |
| 9 | 01f1dd520e091caf9ed87ddafe775154 | Which case queue has the most cases with a block recommendation? |
| 10 | 01f1dd5226591f5e8f85133fd357c9f0 | Which merchant categories have the most block recommendations? |
| 11 | 01f1dd5233111031a068da1537876669 | Why was TXN-0234209 flagged? |

## Other changes

* DECISIONS.md, "Postgres FGAC through views and RLS" bullet only: "no role has a grant on `fraud.*`" now says that since Step 11 only `fraud_lead` has SELECT on `fraud.txn_features` and `fraud.txn_risk_current`, for the two redacting `fraud_dash` views it owns (matches docs/LIMITATIONS.md).
* README.md: new section "For reviewers: read in this order" under "Business outcome"; the old "Read next" list is merged into it (the extra docs/ links kept on one line).
* docs/CONVERSATION_IDS.md: Step 12 row.

## Part D checks

| # | Check | Result | Measured |
| --- | --- | --- | --- |
| 1 | README.md <= 9,000 | PASS | 8,886 |
| 2 | EVIDENCE.md <= 12,000 (limit raised by the user from 9,000) | PASS | 11,914 |
| 3 | DECISIONS.md <= 9,000 | PASS | 8,033 |
| 4 | EVIDENCE.md has Business value, Lakeflow, Unity Catalog, Lakebase, ML and Gen AI, Genie Agent, Databricks App, AI/BI dashboard, Job run | PASS | 9/9 |
| 5 | Every Source line names files in git ls-files | PASS | 23 Source lines, 21/21 files |
| 6 | Every new line verbatim in its own Source file; every number in it found | PASS | 23 blocks; 0 lines missing; 80/80 number tokens found |
| 7 | "not tested as a real non-pii identity" and "fraud_lead \| direct SELECT" absent | PASS | 0, 0 |
| 8 | 8 reading-list files <= 90,000 characters | PASS | 65,123 |
| 9 | 0 em-dash and 0 colleague-name hits in changed files | PASS | 0 em-dash; 0 hits for the first non_pii test user's name |
| 10 | No prompts/ folder and no docs/PROMPTS.md | PASS | 0 files |

Check 9 limit: the second non_pii test user's name could not be looked up (SCIM user lookup returned an error), so it was not grepped. Its user ID is used instead in all files.

Reading list sizes: README.md 8,886; EVIDENCE.md 11,914; DECISIONS.md 8,033; docs/TRACE.md 6,051; docs/LIMITATIONS.md 6,864; BUILD.md 8,954; logs/business_value_2026-11-06.md 5,781; logs/high_value_triage_2026-11-09.md 8,640.

Sample of check 6 (number, source, found): 463,881 / 464,632 / $7,010,482.03 / $10,599,214.95 / $933,889.13 / $1,114,720.20 / 17,630 / 18,135 / 30,956 / 30,993 / 3.89% / 3.99% / 6.83% / 19.9 / 16.0 / 51.1 in business_value_2026-11-06.md: found. 0.950267 / 0.871416 / 0.0 / 439,726 / 94.640% / 22,821 / 4.912% / 2,085 / 0.449% / 0.993762 / 2.1890 / 1.8438 / 0.8253 in batch_scoring_2026-10-20.md: found. 273696236528085 in gold_governance_2026-11-04.md: found. 659281894932228 / 403680627357199 in dashboard_validation_run_659281894932228.md: found. 705 in non_pii_test_user_2026-11-10.md: found. $14,581.03 / 231 / 50 / $10,161.53 in app_permissions_2026-11-09.md + high_value_triage_2026-11-09.md: found.
