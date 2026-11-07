# Evidence index and key results

Moved from README.md in Step 10. The old "All five layers functional" row is now "All six stages functional" and covers the Genie Agent and the App. Short excerpts per stage are in `EVIDENCE.md`. 100% synthetic data.

## Evidence index (Submission Checklist hard gates)

| Hard gate | Evidence (committed files) | Headline number |
| --- | --- | --- |
| All six stages functional | Lakeflow: `card_transaction_bronze_generator.ipynb`, `logs/update_60f6d1de_full_refresh_2026-10-15.md`, `logs/update_c9e70e47_gold_refresh_2026-10-16.md`, `validation_notebooks/gold_feature_validation.ipynb`. Unity Catalog: `logs/gold_governance_2026-11-04.md`, `validation_notebooks/gold_governance_hardening.ipynb`, `validation_notebooks/catalog_grant_narrowing.ipynb`, `uc_app_grants.sql`. Lakebase: `logs/lakebase_sync_2026-10-17.md`, `logs/lakebase_write_path_2026-10-17.md`, `logs/lakebase_scores_sync_2026-10-20.md`. ML / Gen AI: `fraud_model_training.ipynb`, `fraud_batch_scoring.ipynb`, `logs/ml_training_2026-10-20.md`, `fraud_triage_agent.ipynb`, `logs/agent_triage_2026-10-21.md`. Genie Agent: `logs/genie_agent_2026-11-03.md`, `validation_notebooks/genie_agent_validation.ipynb`, `genie_agent_benchmark_evidence_logs/`. App: `logs/app_2026-11-04.md`, `validation_notebooks/app_validation.ipynb`; dashboard `validation_notebooks/dashboard_validation.ipynb`, `logs/dashboard_2026-10-22.md` | 464,632 gold rows, all scored; ROC-AUC 0.8448; agent explains and opens case 2319d4b7; Genie 11/11 as pii and as non_pii; App checks all PASS; 10 dashboard datasets run on the warehouse |
| One connected journey | `docs/TRACE.md`; `logs/lineage_2026-11-01.md` | 11 hops, each with committed text evidence (App hop for TXN-0234209 is a stated gap); 13/19 lineage hops in system tables and 6 filled with labelled next-best evidence |
| Proof it ran | Every `.ipynb` is committed with outputs (counts in `logs/evidence_pass_2026-11-01.md` and `logs/final_verification_2026-11-06.md`); pipeline and job run logs in `logs/` | Job run 1059811930012881 SUCCESS (`logs/job_fe_bar_gold_to_lakebase_run_1059811930012881_2026-11-06.md`) |
| Lakebase synced tables match gold | `validation_notebooks/lakebase_sync_validation.ipynb`, `validation_notebooks/lakebase_scores_validation.ipynb`, `logs/lakebase_scores_sync_2026-10-20.md`, `logs/fgac_hardening_2026-10-21.md` Item 3, `logs/job_fe_bar_gold_to_lakebase_run_1059811930012881_2026-11-06.md` | UC 464,632 = Postgres 464,632 (txn_risk_current, txn_features); 9,289 = 9,289 (customer_risk_profile) |
| Agent case write round trip | `fraud_triage_agent.ipynb` E.2/E.3, `logs/agent_case_roundtrip_2026-10-21.md`, `logs/lakebase_write_path_2026-10-17.md` | Case 2319d4b7 read back as fraud_lead; 1 open case after 2 requests; write p50 33.21 ms / p95 42.40 ms |
| p95 read latency | `logs/lakebase_scores_sync_2026-10-20.md`, `logs/lakebase_fgac_2026-10-21.md` | PK lookup p95 3.18 ms (fraud.txn_risk_current), 5.81 ms (fraud_gov view as fraud_triage_agent) |
| 100% synthetic data | `card_transaction_bronze_generator.ipynb` (seed 42, Faker), `prompts/step1_3458967129203277.md` | 10K customers, 5K merchants, 500K transactions, 50K prior cases, all generated |

## Key results

* **Model** (`logs/ml_training_2026-10-20.md`). Time split at 2026-09-21 15:20:18 (train 371,705 / test 92,927). Test ROC-AUC 0.8448, PR-AUC 0.2808, which is 15.0x the 1.87% prevalence. Precision@100 0.78. The seeded cohort (amt_to_monthly_spend >= 0.5442, cross-border, new device) has a test fraud rate of 18.10% vs 1.87% overall, a 9.70x lift. Non-cohort PR-AUC is 0.2809, so the model learned more than the seeded rule. Thresholds: block 0.950267 (block band precision 0.50, 288 txns), review 0.871416 (block + review recall 0.60).
* **Lakebase latency** (200 PK lookups, reused connection):

| Path | p50 | p95 | p99 | Source |
| --- | --- | --- | --- | --- |
| fraud.txn_features (Step 3) | 2.42 ms | 5.44 ms | 15.65 ms | `logs/lakebase_sync_2026-10-17.md` |
| fraud.txn_risk_current | 2.10 ms | 3.18 ms | 4.38 ms | `logs/lakebase_scores_sync_2026-10-20.md` |
| fraud_gov.txn_risk_current as fraud_triage_agent | 3.82 ms | 5.81 ms | 7.98 ms | `logs/lakebase_fgac_2026-10-21.md` |

* **Deny matrix.** Postgres FGAC 8/8 expected denials, 0 false positives (`logs/lakebase_fgac_2026-10-21.md`). The tamper test for attribution is denied after the hardening fix (`logs/fgac_hardening_2026-10-21.md` Item 7). Dashboard reader role: 9/9 deny tests pass (`logs/dashboard_2026-10-22.md`).
* **Case IDs.** See `docs/TRACE.md` "Case IDs".
* **Dashboard live read.** The agent opened case 030dc7fb. With no sync or job in between, the dashboard KPI query went from cases_created_today 0 / open_cases 6 / visible_cases 164 (01:45:19 UTC) to 1 / 7 / 165 (01:45:41 UTC) on 2026-10-23.
* **Business value.** See `logs/business_value_2026-11-06.md` and `README.md`.
