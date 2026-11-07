# Final verification (Step 10, 2026-11-06)

Run by alex.owen@databricks.com in conversation 1883459888084300, workspace fevm-workshop-guy. Checked on the step10 working tree against the baseline origin/main f6d6fd4, before the merge. The post-merge checks on origin/main are in the Step 10 merge commit message. All checks are read-only.

## G1. Notebooks (code cells, with output, error outputs)

| Notebook | Step 10 | Baseline f6d6fd4 | Result |
| --- | --- | --- | --- |
| card_transaction_bronze_generator.ipynb | 9, 8, 0 | 9, 8, 0 | Unchanged. One code cell had no output in the baseline too |
| fraud_batch_scoring.ipynb | 8, 8, 0 | 8, 8, 0 | PASS |
| fraud_model_training.ipynb | 11, 11, 0 | 11, 11, 0 | PASS |
| fraud_triage_agent.ipynb | 9, 9, 0 | 9, 9, 0 | PASS |
| validation_notebooks/app_validation.ipynb | 7, 7, 0 | 7, 7, 0 | PASS |
| validation_notebooks/business_value.ipynb | 8, 8, 0 | new | PASS |
| validation_notebooks/catalog_grant_narrowing.ipynb | 3, 3, 0 | 3, 3, 0 | PASS |
| validation_notebooks/dashboard_validation.ipynb | 15, 15, 0 | 15, 15, 0 | PASS |
| validation_notebooks/fgac_hardening.ipynb | 10, 10, 0 | 10, 10, 0 | PASS |
| validation_notebooks/genie_agent_validation.ipynb | 16, 16, 0 | 16, 16, 0 | PASS |
| validation_notebooks/gold_feature_validation.ipynb | 4, 4, 0 | 4, 4, 0 | PASS |
| validation_notebooks/gold_governance_hardening.ipynb | 6, 6, 0 | 6, 6, 0 | PASS |
| validation_notebooks/lakebase_fgac_validation.ipynb | 8, 8, 0 | 8, 8, 0 | PASS |
| validation_notebooks/lakebase_scores_validation.ipynb | 6, 6, 0 | 6, 6, 0 | PASS |
| validation_notebooks/lakebase_sync_validation.ipynb | 7, 7, 0 | 7, 7, 0 | PASS |
| validation_notebooks/lakebase_write_path_validation.ipynb | 10, 10, 0 | 10, 10, 0 | PASS |
| validation_notebooks/lineage_validation.ipynb | 7, 7, 0 | 7, 7, 0 | PASS |

## G2. logs/ by extension

.md 32 (with this file), .json 11, .html 1. No .txt, .csv or .log files. The one .html (`logs/dashboard_validation_run_659281894932228.html`) has a .md copy, `logs/dashboard_validation_run_659281894932228.md`.

## G3. Six-stage and link check

* README.md: 23 relative links, 0 missing. Every backticked logs/, validation_notebooks/, docs/ and genie/ path exists.
* EVIDENCE.md, DECISIONS.md, BUILD.md and the 8 docs/ files: 0 missing links.
* EVIDENCE.md, 13 excerpt blocks: path exists, the quoted section is found in the source file, every excerpt line is found in it, and every number in the excerpt is found in it. 13 of 13 are all yes.

| Stage | Source | Run ID | All yes |
| --- | --- | --- | --- |
| Lakeflow | logs/update_60f6d1de_full_refresh_2026-10-15.md | update 60f6d1de | yes |
| Unity Catalog | logs/gold_governance_2026-11-04.md (2 blocks) | job run 273696236528085 | yes |
| Lakebase | logs/lakebase_scores_sync_2026-10-20.md, logs/lakebase_fgac_2026-10-21.md | sync update 31370778 | yes |
| ML and Gen AI | logs/ml_training_2026-10-20.md, logs/agent_triage_2026-10-21.md, logs/agent_case_roundtrip_2026-10-21.md | MLflow run d89beaca, trace tr-2fb3e5d6 | yes |
| Genie Agent | logs/genie_agent_2026-11-03.md, genie_agent_benchmark_evidence_logs/non_pii_test_user_2026-11-05.md | conversation 01f1d8ac | yes |
| Databricks App | logs/app_2026-11-04.md (2 blocks) | deployment 01f1d98e | yes |
| Job run | logs/job_fe_bar_gold_to_lakebase_run_1059811930012881_2026-11-06.md | run 1059811930012881 | yes |

## G4. Sizes (characters)

| File | Characters |
| --- | --- |
| README.md | 8,190 |
| EVIDENCE.md | 6,594 |
| DECISIONS.md | 7,400 |
| BUILD.md | 8,981 |
| docs/ARCHITECTURE.md | 4,883 |
| docs/CONVERSATION_IDS.md | 2,913 |
| docs/EVIDENCE_INDEX.md | 4,893 |
| docs/HOW_TO_RUN.md | 3,900 |
| docs/LIMITATIONS.md | 5,264 |
| docs/PROMPTS.md | 2,109 |
| docs/RESOURCES.md | 8,207 |
| docs/TRACE.md | 6,051 |
| logs/final_verification_2026-11-06.md | under 9,000 (measured after writing) |

* Priority reading set (README, EVIDENCE, DECISIONS, BUILD, logs/business_value_2026-11-06.md, the two pipeline SQL files, docs/): 87,204 characters, under 90,000.
* Repo before (origin/main f6d6fd4): 93 files, 1,883,894 characters. After: 108 files with this log. 15 files were added and 1 was renamed.
* No files were deleted: the user chose no cuts in Part F. 48 files stay over 9,000 characters: notebooks, source, prompts and raw logs.

## G5. Commit authorship on main (git shortlog -sne, before the Step 10 merge)

| Author | Commits |
| --- | --- |
| alex.owen@databricks.com <alex.owen@databricks.com> | 46 |
| aowen5000 <aowen5000@gmail.com> | 15 |
| Alex Owen <aowen5000@gmail.com> | 2 |

Both emails are mine (README.md "Commit identities"). History was not rewritten.

## G6. Token scan

Patterns: dapi, eyJ, ghp_, gho_, password=, -----BEGIN. There are 18 hits and none is a secret. They are code passing a variable (`password=self._token`, `password=tok`, `password=token`, `password=TOKEN`), a regex in the genie_agent_validation output, and the pattern list itself in the prompt and log text. Nothing was redacted.

## G7. Real customer data

README.md states "100% synthetic". The Databricks account list was not available in this session, so no file could be checked against it. The generator uses Faker with seed 42. Report only.

## G8. Governance state (report only, unchanged)

* Genie space 01f1d7b464d510b9aa6cde48300787ca: CAN_RUN for the App service principal 8f239f44-078a-4f8f-90f1-4c1b0bcdc26c and for the non_pii test user (user ID 72697000497660), both direct. CAN_MANAGE for alex.owen and admins (inherited). The `non_pii` group itself has no entry.
* App service principal UC grants: SELECT on `fraud_dash.{baseline_comparison, case_actions_daily, case_summary, exposure, score_distribution, triage_queue}` and `fe_bar_a0.risk_score_calibration`. USE CATALOG and USE SCHEMA on both paths. READ METADATA only on `scored_transactions`, `txn_features_gold`, `customer_risk_profile_gold` and `fraud_dash.model_thresholds`. BROWSE, CREATE SCHEMA and READ METADATA on `workshop_guy_catalog` come from `account users`.
* Row filters in fe_bar_a0: `fact_transactions_silver` and `txn_features_gold` (`filter_high_amount_txns`). No row filter on `scored_transactions`.
* Column masks in fe_bar_a0: `dim_customer_silver.avg_monthly_spend` and `customer_risk_profile_gold.avg_amount_30d`. `txn_features_gold.amt_to_monthly_spend` is unmasked.

## G9. Em-dash check

0 em-dashes in README.md, EVIDENCE.md, DECISIONS.md, BUILD.md, the 8 docs/ files, logs/business_value_2026-11-06.md, logs/job_fe_bar_gold_to_lakebase_run_1059811930012881_2026-11-06.md, logs/gold_governance_2026-11-04.md, genie_agent_benchmark_evidence_logs/README.md and genie_agent_benchmark_evidence_logs/non_pii_test_user_2026-11-05.md.

## Left as is, with reason

* "Layer 5" in `lakebase_dashboard.sql` line 2 and `lakebase_fgac.sql` line 320 is a SQL comment in committed source. I did not edit source in this docs-only step.
* "Layer 5" in `logs/dashboard_validation_run_659281894932228.md` line 17: a copy of committed notebook output.
* `docs/ARCHITECTURE.md` line 3 and `docs/EVIDENCE_INDEX.md` line 3 quote the old wording only to say it was replaced by the six stages.
* "Layer 5" in `validation_notebooks/dashboard_validation.ipynb`: committed notebook output.
* "five layers" and "Layer 5" in `prompts/step6_*` and `prompts/step7_*`, and the old tester filename in `prompts/step10_1883459888084300.md`: verbatim prompts.
* The tester's name in the committed output of `validation_notebooks/gold_governance_hardening.ipynb`: notebook output.
