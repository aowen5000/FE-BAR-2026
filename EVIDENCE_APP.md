# Evidence per stage, part 2: Databricks App, high-value triage and job run

Continued from [EVIDENCE.md](EVIDENCE.md), which covers Business value and stages 1 to 5. Split because the scorer reads only the first 9,000 characters of each file. 100% synthetic data.

### Databricks App (surface it to the business)

```
| Live-test case | `5af3575c-cda8-47cb-97be-021b26dca000` (TXN-0045116), db_inserted_by = the app role |
| Validation | `validation_notebooks/app_validation.ipynb`: 15/15 PASS |
| D.4 Exactly one case for the txn after repeat clicks | PASS |
| D.4 Case visible in UC `fraud_dash.case_summary`, no sync or job in between | PASS |
```

Source: logs/app_2026-11-04.md, sections "Summary" and "Part D results"; deployment 01f1d98ebd6c1954bd2d4b7f9d7c6ae5, case 5af3575c-cda8-47cb-97be-021b26dca000, Genie conversation 01f1d98f28021142877f6ea599ede8a1.

#### AI/BI dashboard

```
* Job run: 659281894932228 (one-time submit, serverless), task run 403680627357199 (attempt 1, SUCCESS)
  "dashboard_id": "01f1ce7f835a1e81b05ebb664bf0994c",
[2026-10-23 02:24:04.834 UTC] setup done. Dashboard 'FE Bar Fraud Ops: Triage & Action' has 10 datasets: ['ds_kpi_cases', 'ds_model_vs_baseline', 'ds_score_dist', 'ds_cases_daily', 'ds_actions_daily', 'ds_triage', 'ds_triage_options', 'ds_recent_cases', 'ds_calibration', 'ds_exposure']
PASS: live read. case c2b2ec3a-a1a7-444f-a1c8-969af362c0ee for TXN-0197951 is visible to the dashboard's dataset queries with no sync or job.
```

Source: logs/dashboard_validation_run_659281894932228.md, header, cells "Setup", "D.2" and "Summary"; job run 659281894932228, case c2b2ec3a-a1a7-444f-a1c8-969af362c0ee, trace tr-6659ce2b852915f489c9add9eef92cbd.

```
Published with embedded credentials; all 11 datasets load.
```

Source: logs/high_value_triage_2026-11-09.md, section "Genie and dashboard"; dashboard 01f1ce7f835a1e81b05ebb664bf0994c.

### High-value triage (Step 11)

```
| triage_queue high-value rows | 0 | 705 (= Postgres as fraud_triage_agent: 705) |
| Non-null amount on high-value rows (triage_queue, case_summary) | n/a | 0, 0 |
| baseline_comparison | model $7,010,482.03 vs rule $933,889.13 caught | identical |
| Reader role_table_grants | 19 rows | 19 rows, 0 added, 0 removed; no memberships |
```

Source: logs/high_value_triage_2026-11-09.md, section "Before vs after"; validation_notebooks/high_value_triage.ipynb 24 PASS / 0 FAIL; App deployment 01f1dcc1df121891906c3a2c6df85a1a, case d2a1d4a1-7f84-4ed9-b9aa-4146c9f57592.

```
| alex.owen@databricks.com | CAN_MANAGE | no |
| group pii | CAN_USE | no |
| group admins | CAN_MANAGE | yes, from the workspace apps permissions |
Validation `validation_notebooks/high_value_triage.ipynb` E.8b: PASS (`pii` CAN_USE present, no `users` grant).
* **non_pii test user at the App URL: denied, no text evidence.**
| Search TXN-0189627 | found: $14,581.03, block, rank 231 |
| High-value only | 50 rows, min amount $10,161.53, first TXN-0189627 |
```

Source: logs/app_permissions_2026-11-09.md, sections "After" and "Notes"; logs/high_value_triage_2026-11-09.md, section "App (app/app.py only)"; deployment 01f1dcc1df121891906c3a2c6df85a1a, case d2a1d4a1-7f84-4ed9-b9aa-4146c9f57592.

### Job run (Step 10, Part C)

```
| gold_pipeline_refresh | 1050818699563606 | TERMINATED | SUCCESS | 63 s |
| batch_scoring | 1086396456455747 | TERMINATED | SUCCESS | 151 s |
| lakebase_sync_refresh | 455481036519417 | TERMINATED | SUCCESS | 53 s |
risk_score unchanged vs pre-run 0.9844108757126732: True. Only scored_at moved, as expected for a re-score.
```

Source: logs/job_fe_bar_gold_to_lakebase_run_1059811930012881_2026-11-06.md, sections "Tasks" and "Traced transaction TXN-0234209"; job 1115396029932218, run 1059811930012881, SDP update e07e06df-7470-473b-bf75-3941d56deba5, sync update daedd8c1-5334-4287-a06d-154fe7cebe9f.
