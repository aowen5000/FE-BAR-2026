# Non-pii benchmark run: Connor Hauenstein (2026-11-05)

- Identity: Connor Hauenstein, user ID 72697000497660, member of account group `non_pii` only (not `pii`). CAN_RUN on the space granted directly.
- Conversation: `01f1d8ac352915faaffdcb33c40ce9e4` (one conversation, Agent mode), 11 messages, 2026-11-05 about 00:02–00:08 UTC.
- Attribution: `user_id` on every message (Genie message API, read as space owner).
- Grading: same expected values as rounds 0–2. Permission errors: none.

| # | Message ID | Question | Source in Genie SQL | Answer (key values) | Result |
| --- | --- | --- | --- | --- | --- |
| 1 | 01f1d8ac358b14c2b2ab4089331b5450 | How much fraud did the model catch vs the baseline rule? | fraud_dash.baseline_comparison | $7,010,482 vs $933,889; 6,571 vs 2,767 | PASS |
| 2 | 01f1d8ac46ed187fbb87eb49b060a01f | What is the block-band precision? | fe_bar_a0.risk_score_calibration | 0.5 (144/288) | PASS |
| 3 | 01f1d8ac56431edcbbbf6673bcd1758b | Why was TXN-0234209 flagged? | fraud_dash.triage_queue | 0.984 block; is_new_device +2.57, geo_distance_from_home +1.87, is_online +1.20; 4 columns (JSON kept) | PASS |
| 4 | 01f1d8ac5f271ff0b07a472b79cda4b5 | Which merchant categories have the most block recommendations? | none (refusal) | merchant category not available | PASS |
| 5 | 01f1d8ac6b05184f88c67238276ab97b | How many open cases are in each queue? | fraud_dash.case_summary | auto_block 9 | PASS |
| 6 | 01f1d8ac942e1f269c8556a040b7af4b | How many cases were opened between October 20 and October 23, 2026? | case_actions_daily + case_summary | 121 | PASS |
| 7 | 01f1d8acb27616d0b59e0d3559777e9f | How many cases were created per day and queue in the week starting October 19, 2026? | fraud_dash.case_summary | 10-20 AR 1; 10-21 AR 56, AB 7; 10-23 AR 54, AB 3 | PASS |
| 8 | 01f1d8acc03916d2a7737c6e3bcc6c98 | Which 5 customers have the most flagged transactions in the triage queue? | fraud_dash.triage_queue | CUST-01399 20, CUST-00167 17, CUST-03895/04867/06862 16 | PASS |
| 9 | 01f1d8acd0521598a0835a0e1ced8d5a | What is the average monthly spend for customer CUST-08669? | none (refusal) | not available; amt_to_monthly_spend masked | PASS |
| 10 | 01f1d8acda641c36ad54959829ca31ca | How many fraud dollars did the model miss, and how many false positives did it generate? | fraud_dash.exposure | $975,726 missed; 17,630 false positives | PASS |
| 11 | 01f1d8ace3441c15bb4d1d2582eb27fa | Which case queue has the most cases with a block recommendation? | fraud_dash.case_summary | auto_block 10 | PASS |

Result: 11/11 PASS, identical to the pii runs. No amount over $10,000 and no monthly-spend value appeared.
