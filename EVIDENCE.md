# Evidence per stage

Key output lines copied as text from committed files, in the six-stage order of [README.md](README.md#six-required-stages). Each block is followed by its source. 100% synthetic data. The full index is in `docs/EVIDENCE_INDEX.md`.

### Lakeflow (ingest)

```
| Dataset | Type | Status | Rows Written | Rows Dropped |
| `dim_customer_silver` | MATERIALIZED_VIEW | COMPLETED | 9,289 | 1 |
| `dim_merchant_silver` | MATERIALIZED_VIEW | COMPLETED | 4,666 | 1 |
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
  * Non-pii view, computed from the filter's non-pii branch: 463,881 of 464,632 rows in `txn_features_gold`; avg_amount_30d NULL. This was not tested as a real non-pii identity.
```

Source: logs/gold_governance_2026-11-04.md, section "Job / sync test"; job run 273696236528085, sync update d1502c56.

```
* **Checks: 29/29 PASS.**
  * `fe_bar_a0` has USE SCHEMA only, with SELECT on the 5 objects.
  * No `account users` privilege on `scored_transactions`, `txn_features_gold`, the 4 bronze tables or the `staging` volume.
  * The owner identity still reads `scored_transactions` (464,632 rows).
```

Source: logs/gold_governance_2026-11-04.md, section "Catalog grant narrowing"; no run ID (SQL applied by the user from validation_notebooks/catalog_grant_narrowing.ipynb).

### Lakebase (operational serving)

```
| UC scored_transactions | 464,632 | 2026-10-20 02:40:39.012983 |
| Postgres fraud.txn_risk_current | 464,632 | 2026-10-20 02:40:39.012983+00:00 |
Match: True (model_version 1..1). After job run 379167641926204 both are still 464,632, with scored_at 2026-10-20 04:38:02.628263.
| p50 | 2.10 ms |
| p95 | 3.18 ms |
| p99 | 4.38 ms |
```

Source: logs/lakebase_scores_sync_2026-10-20.md, sections "Row count match" and "Read latency"; sync pipeline f8690359-4bb1-45b9-8fdb-5bd892239db2, update 31370778-aca4-4b74-8a0c-062e953c4a3e.

```
| fraud_analyst | INSERT case | permission denied for table fraud_cases |
| fraud_triage_agent | DELETE case | permission denied for table fraud_cases |
| fraud_triage_agent | INSERT wrong created_by | new row violates row-level security policy |
| fraud_lead | direct SELECT fraud.txn_features | permission denied for table txn_features |
```

Source: logs/lakebase_fgac_2026-10-21.md, section "Deny Test Results (all DENIED as expected)"; no run ID.

### ML and Gen AI (make it intelligent)

```
| ROC-AUC | 0.8448 |
| PR-AUC | 0.2808 |
| Precision@100 | 0.7800 |
| block | 288 | 0.31% | 144 | 0.5000 | 0.0830 |
| review | 3,567 | 3.84% | 897 | 0.2515 | 0.5170 |
```

Source: logs/ml_training_2026-10-20.md, sections "Test-set metrics" and "Thresholds for recommended_action (logged as MLflow params)"; MLflow run d89beaca8f81447780da60ed2ea7c811.

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
| 1 | 01f1d8ac358b14c2b2ab4089331b5450 | How much fraud did the model catch vs the baseline rule? | fraud_dash.baseline_comparison | $7,010,482 vs $933,889; 6,571 vs 2,767 | PASS |
| 10 | 01f1d8acda641c36ad54959829ca31ca | How many fraud dollars did the model miss, and how many false positives did it generate? | fraud_dash.exposure | $975,726 missed; 17,630 false positives | PASS |
Result: 11/11 PASS, identical to the pii runs. No amount over $10,000 and no monthly-spend value appeared.
```

Source: genie_agent_benchmark_evidence_logs/non_pii_test_user_2026-11-05.md, section "Non-pii benchmark run"; Genie conversation 01f1d8ac352915faaffdcb33c40ce9e4 (non_pii test user, user ID 72697000497660).

### Databricks App (surface it to the business)

```
| Live-test case | `5af3575c-cda8-47cb-97be-021b26dca000` (TXN-0045116), db_inserted_by = the app role |
| Validation | `validation_notebooks/app_validation.ipynb`: 15/15 PASS |
```

Source: logs/app_2026-11-04.md, section "Summary"; deployment 01f1d98ebd6c1954bd2d4b7f9d7c6ae5, Genie conversation 01f1d98f28021142877f6ea599ede8a1.

```
| D.4 db_inserted_by is the app Postgres role | PASS |
| D.4 Exactly one case for the txn after repeat clicks | PASS |
| D.4 Case visible in UC `fraud_dash.case_summary`, no sync or job in between | PASS |
| D.4 Genie numbers match `baseline_comparison` at check time | PASS: model $7,010,482.03 vs baseline $933,889.13 (same as Step 8) |
| D.6 No case written | PASS (228 -> 228) |
```

Source: logs/app_2026-11-04.md, section "Part D results"; case 5af3575c-cda8-47cb-97be-021b26dca000.

### High-value triage (Step 11)

```
| triage_queue high-value rows | 0 | 705 (= Postgres as fraud_triage_agent: 705) |
| Non-null amount on high-value rows (triage_queue, case_summary) | n/a | 0, 0 |
| baseline_comparison | model $7,010,482.03 vs rule $933,889.13 caught | identical |
| Reader role_table_grants | 19 rows | 19 rows, 0 added, 0 removed; no memberships |
```

Source: logs/high_value_triage_2026-11-09.md, section "Before vs after"; validation_notebooks/high_value_triage.ipynb 24 PASS / 0 FAIL; App deployment 01f1dcc1df121891906c3a2c6df85a1a, case d2a1d4a1-7f84-4ed9-b9aa-4146c9f57592.

### Job run (Step 10, Part C)

```
| gold_pipeline_refresh | 1050818699563606 | TERMINATED | SUCCESS | 63 s |
| batch_scoring | 1086396456455747 | TERMINATED | SUCCESS | 151 s |
| lakebase_sync_refresh | 455481036519417 | TERMINATED | SUCCESS | 53 s |
| Postgres fe_bar_db fraud.txn_risk_current | 464632 |
| All equal | True |
risk_score unchanged vs pre-run 0.9844108757126732: True. Only scored_at moved, as expected for a re-score.
```

Source: logs/job_fe_bar_gold_to_lakebase_run_1059811930012881_2026-11-06.md, sections "Tasks", "Row counts: UC = Postgres" and "Traced transaction TXN-0234209"; job 1115396029932218, run 1059811930012881, SDP update e07e06df-7470-473b-bf75-3941d56deba5, sync update daedd8c1-5334-4287-a06d-154fe7cebe9f.
