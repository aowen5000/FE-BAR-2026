# Non-pii benchmark run: second non_pii test user (2026-11-10, Step 11)

- Identity: a second non_pii test user, user ID 76510230734315, member of group `non_pii` only (not `pii`, not `admins`). Not the user from the 2026-11-05 run.
- Conversations: 11, one question each, in the Genie UI, 2026-11-10 21:41 to 22:00 UTC (after the Step 11 space update at 04:47 to 04:54 UTC).
- Attribution: `user_id` on every message (Genie message API, read as space owner).
- Grading: same rule as `validation_notebooks/high_value_triage.ipynb` B.7 (every expected value appears in the returned rows; refusal benchmarks must return no rows), against the live expected SQL. Re-graded 2026-11-10 22:26 UTC. Permission errors on the questions: none.
- Benchmark change before grading (approved by the user): the expected SQL of "Show the top 5 high-value block transactions..." no longer selects `risk_score`. Genie returned the right 5 rows in order but without that column, which failed the strict grader. Filter, sort and LIMIT unchanged; the pii answers still pass.

| # | Message ID | Question | Source in Genie SQL | Answer (key values) | Result |
| --- | --- | --- | --- | --- | --- |
| 1 | 01f1dd4f81aa176b8882dc78d44eb40f | How many high-value transactions are in the triage queue? | fraud_dash.triage_queue | 705 | PASS |
| 2 | 01f1dd5004361b59bd0aede677eb6fb7 | Show the top 5 high-value block transactions in the triage queue with their amount band | fraud_dash.triage_queue | TXN-0189627 (231), TXN-0193357 (901), TXN-0371350 (935), TXN-0291011 (936), TXN-0448721 (939), all over_10k, no amount column | PASS |
| 3 | 01f1dd50268c1e2b9d31d9e48ed76e08 | How many cases were created per day and queue in the week starting October 19, 2026? | fraud_dash.case_summary | 10-20 AR 1; 10-21 AR 56, AB 8; 10-23 AR 54, AB 4 | PASS |
| 4 | 01f1dd504fe515659545ce9dfb402a7d | How many cases were opened between October 20 and October 23, 2026? | fraud_dash.case_actions_daily | 121 | PASS |
| 5 | 01f1dd50dc071d33a8f1afb2b351f5a5 | How many fraud dollars did the model miss, and how many false positives did it generate? | fraud_dash.baseline_comparison | $975,725.89 missed; 17,630 false positives | PASS |
| 6 | 01f1dd51810c10b0be3bc5fef739f919 | How many open cases are in each queue? | fraud_dash.case_summary | auto_block 11 | PASS |
| 7 | 01f1dd5197991ca3aeb5f4bc13a984bc | What is the average monthly spend for customer CUST-08669? | none (refusal) | not available in this space | PASS |
| 8 | 01f1dd51e3f51147aae3b4f225022bb0 | Which 5 customers have the most flagged transactions in the triage queue? | fraud_dash.triage_queue | CUST-01399 20, CUST-00167 17, CUST-00358 17, CUST-03895 16, CUST-04867 16 | PASS |
| 9 | 01f1dd520e2d1708921e905c07c4243c | Which case queue has the most cases with a block recommendation? | fraud_dash.case_summary | auto_block 16 | PASS |
| 10 | 01f1dd52268110ac9925b88262733ac3 | Which merchant categories have the most block recommendations? | none (refusal) | merchant category not available | PASS |
| 11 | 01f1dd5233341b26a4203f7deae93ab6 | Why was TXN-0234209 flagged? | fraud_dash.triage_queue | 0.984 block; is_new_device +2.57, geo_distance_from_home +1.87, is_online +1.20 | PASS |

Result: 11/11 PASS of the 11 asked; both new Step 11 benchmarks (1, 2) pass. Not asked: "How much fraud did the model catch vs the baseline rule?" and "What is the block-band precision?" The user accepted 11 of 13 for E.10c. No amount over $10,000 and no monthly-spend value appeared. Results 3, 6, 8 and 9 differ from the 2026-11-05 run. Most of the change is because case_summary and triage_queue now include high-value rows (`logs/high_value_triage_2026-11-09.md`). Results 6 and 9 also include one case opened between 2026-11-05 and the Step 11 Part A capture (open auto_block 9 to 10, block cases 10 to 11 before Step 11).

## App URL attempt (E.8c)

Skipped by the user. `system.access.audit` shows 6 `mintOAuthAuthorizationCode` events for this user with client ID `ef875206-4d65-467e-b3d4-491e8be54f48` (the App's `oauth2_app_client_id`), at 21:39:57, 21:40:10 and 22:01:12 to 22:01:24 UTC, all status 200, and 2 `oidcTokenAuthorization` events at 22:01:23 to 22:01:24 from an internal service. These show sign-in to the App's OAuth client, not whether the App proxy allowed or denied the request; that decision is not in the audit log. The App ACL gives this user no permission (`logs/app_permissions_2026-11-09.md`). No screenshot was provided, so E.8c is recorded as skipped, not PASS.
