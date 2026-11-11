# Evidence per stage

Key output lines copied as text from committed files, in the six-stage order of [README.md](README.md#six-required-stages), each followed by its source. 100% synthetic data. Index: `docs/EVIDENCE_INDEX.md`.

### Business value

```
| Headline KPI | governed view (excludes amount > 10000), 463,881 txns | full synthetic set, 464,632 txns |
| Fraud $ caught, model | $7,010,482.03 | $10,599,214.95 |
| Fraud $ caught, baseline rule | $933,889.13 | $1,114,720.20 |
| False positives, model | 17,630 | 18,135 |
| False positives, baseline rule | 30,956 | 30,993 |
| False positive rate, model | 3.89% | 3.99% |
| False positive rate, baseline rule | 6.83% | 6.83% |
| Agent run, end to end (explain, act, guardrail) | 9 | 19.9 s | 16.0 to 51.1 s | 2 to 3 min per case (assumption includes analyst reading time) |
```

Source: logs/business_value_2026-11-06.md, sections "B.4b-3 Headline KPIs in two scopes" and "B.3b"; validation_notebooks/business_value.ipynb, no run ID in the log.

```
| triage_queue high-value rows | 0 | 705 (= Postgres as fraud_triage_agent: 705) |
```

Source: logs/high_value_triage_2026-11-09.md, section "Before vs after"; App deployment 01f1dcc1df121891906c3a2c6df85a1a.

Analyst minutes per case are planning assumptions, not measurements.

### Lakeflow (ingest)

```
| Dataset | Type | Status | Rows Written | Rows Dropped |
| `fact_transactions_silver` | MATERIALIZED_VIEW | COMPLETED | 464,679 | 17,932 |
| `fact_prior_fraud_cases_silver` | MATERIALIZED_VIEW | COMPLETED | 46,417 | 1,755 |
**Total rows ingested (bronze):** 607,463
**Total rows dropped by expectations:** 19,689
```

Source: logs/update_60f6d1de_full_refresh_2026-10-15.md, section "Dataset Results"; Spark Declarative Pipeline c0db28b8-dbd2-432d-99cf-4ea2aea60274, update 60f6d1de-d62b-4deb-9701-0455c5c748ea.

### Unity Catalog (govern)

```
* After-checks: 25/25 PASS (notebook cell 4).
  * The pii reader still sees the 751 rows with amount > 10000, and sum(avg_amount_30d) = 2,010,281.99 is unchanged.
```

Source: logs/gold_governance_2026-11-04.md, section "Job / sync test"; job run 273696236528085, sync update d1502c56.

```
| `txn_features_gold` | Row filter `filter_high_amount_txns` ON (`amount`) | `WITH ROW FILTER` in `gold_feature_layer.sql`, applied by the pipeline update in job run 273696236528085 | In place |
| `customer_risk_profile_gold` | New mask `mask_avg_amount_30d` on `avg_amount_30d` (`IF(IS_ACCOUNT_GROUP_MEMBER('pii'), avg_amount_30d, NULL)`) | New UC function plus a column list with `MASK` in `gold_feature_layer.sql` | In place |
| `scored_transactions` | Row filter `filter_high_amount_txns` ON (`amount`) | `ALTER TABLE ... SET ROW FILTER` | Removed again (option B, below) |
```

Source: logs/gold_governance_2026-11-04.md, section "Changes"; job run 273696236528085.

```
* Row filters in fe_bar_a0: `fact_transactions_silver` and `txn_features_gold` (`filter_high_amount_txns`). No row filter on `scored_transactions`.
```

Source: logs/final_verification_2026-11-06.md, section "G8. Governance state (report only, unchanged)"; conversation 1883459888084300.

Real non_pii identity test: see the Genie Agent block (non_pii test user, 0 amounts over $10,000 returned).

```
* **Checks: 29/29 PASS.**
  * No `account users` privilege on `scored_transactions`, `txn_features_gold`, the 4 bronze tables or the `staging` volume.
```

Source: logs/gold_governance_2026-11-04.md, section "Catalog grant narrowing"; no run ID (SQL applied by the user from validation_notebooks/catalog_grant_narrowing.ipynb).

### Lakebase (operational serving)

```
| UC scored_transactions | 464,632 | 2026-10-20 02:40:39.012983 |
| Postgres fraud.txn_risk_current | 464,632 | 2026-10-20 02:40:39.012983+00:00 |
Match: True (model_version 1..1). After job run 379167641926204 both are still 464,632, with scored_at 2026-10-20 04:38:02.628263.
| p50 | 2.10 ms |
| p95 | 3.18 ms |
```

Source: logs/lakebase_scores_sync_2026-10-20.md, sections "Row count match" and "Read latency"; sync pipeline f8690359-4bb1-45b9-8fdb-5bd892239db2, update 31370778-aca4-4b74-8a0c-062e953c4a3e.

```
| fraud_analyst | INSERT case | permission denied for table fraud_cases |
| fraud_triage_agent | DELETE case | permission denied for table fraud_cases |
| fraud_triage_agent | INSERT wrong created_by | new row violates row-level security policy |
| fraud_analyst | direct SELECT fraud.txn_features | permission denied for table txn_features |
```

Source: logs/lakebase_fgac_2026-10-21.md, section "Deny Test Results (all DENIED as expected)"; no run ID.

Since Step 11 one governed role has a grant on `fraud.*`: `fraud_lead` (no login, member of `fraud_pii`) has SELECT on `fraud.txn_features` and `fraud.txn_risk_current`, so the two redacting `fraud_dash` views it owns can read high-value rows. No other governed role (`fraud_analyst`, `fraud_triage_agent`, `fraud_pii`, the UC reader) has a grant on `fraud.*`, and the only member of `fraud_lead` is alex.owen (checked 2026-11-10). (docs/LIMITATIONS.md, "Carried over")

### ML and Gen AI (make it intelligent)

```
| ROC-AUC | 0.8448 |
| PR-AUC | 0.2808 |
| Precision@100 | 0.7800 |
```

Source: logs/ml_training_2026-10-20.md, section "Test-set metrics"; MLflow run d89beaca8f81447780da60ed2ea7c811.

```
| block_threshold | 0.950267 |
| review_threshold | 0.871416 |
Consistency check: max |registered pyfunc predict - distributed score| on 1,000 rows = **0.0**.
| approve | 439,726 | 94.640% |
| review | 22,821 | 4.912% |
| block | 2,085 | 0.449% |
| TXN-0147293 | CUST-07061 | 2026-05-22 13:56:00 | 49.59 | 0.993762 | block | is_new_device=1.0 (+2.1890), geo_distance_from_home=160.17 (+1.8438), risk_segment=high (+0.8253) |
```

Source: logs/batch_scoring_2026-10-20.md, sections "Inputs read from the champion run params (nothing hardcoded)", "recommended_action distribution" and "Top 10 highest-risk transactions"; MLflow run d89beaca8f81447780da60ed2ea7c811.

```
Trace ID: tr-2fb3e5d6190f61225d050ad0d35e23d8
Latency: 43.4s
Case ID: 2319d4b7-bea3-412b-ba6b-8325e1a7a71d
Action: block, Queue: auto_block, created_by: fraud_triage_copilot:agent
```

Source: logs/agent_triage_2026-10-21.md, section "E.2 Act"; trace tr-2fb3e5d6190f61225d050ad0d35e23d8.

```
- Second call to open a case for TXN-0234209 returned the same case_id: 2319d4b7
- Only 1 open case exists for TXN-0234209 after two "open case" requests
- The partial unique index (status != 'closed') prevents duplicate open cases
```

Source: logs/agent_case_roundtrip_2026-10-21.md, section "Idempotency Result"; case 2319d4b7-bea3-412b-ba6b-8325e1a7a71d.

### Genie Agent (natural language)

```
Total: round 0 = 11/11 PASS, round 1 = 11/11 PASS.
```

Source: logs/genie_agent_2026-11-03.md, section "Benchmarks (Conversation API, final round = round 1)"; Genie space 01f1d7b464d510b9aa6cde48300787ca, identity alex.owen (pii).

```
| Genie | 13/13 PASS as pii (11 existing + 2 new) |
```

Source: logs/high_value_triage_2026-11-09.md, section "Summary"; Genie space 01f1d7b464d510b9aa6cde48300787ca, conversation 4443667514456316.

```
| 1 | 01f1d8ac358b14c2b2ab4089331b5450 | How much fraud did the model catch vs the baseline rule? | fraud_dash.baseline_comparison | $7,010,482 vs $933,889; 6,571 vs 2,767 | PASS |
| 10 | 01f1d8acda641c36ad54959829ca31ca | How many fraud dollars did the model miss, and how many false positives did it generate? | fraud_dash.exposure | $975,726 missed; 17,630 false positives | PASS |
Result: 11/11 PASS, identical to the pii runs. No amount over $10,000 and no monthly-spend value appeared.
```

Source: genie_agent_benchmark_evidence_logs/non_pii_test_user_2026-11-05.md, section "Non-pii benchmark run"; Genie conversation 01f1d8ac352915faaffdcb33c40ce9e4 (non_pii test user, user ID 72697000497660).

```
| 1 | 01f1dd4f81aa176b8882dc78d44eb40f | How many high-value transactions are in the triage queue? | fraud_dash.triage_queue | 705 | PASS |
Result: 11/11 PASS of the 11 asked; both new Step 11 benchmarks (1, 2) pass.
No amount over $10,000 and no monthly-spend value appeared.
```

Source: genie_agent_benchmark_evidence_logs/non_pii_test_user_2026-11-10.md, section "Non-pii benchmark run: second non_pii test user (2026-11-10, Step 11)"; Genie conversation 01f1dd4f81751476806ff924ef6934bb, first of 11 (non_pii test user, user ID 76510230734315).

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
