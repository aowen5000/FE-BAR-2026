# Notebook outputs evidence re-run (2026-10-23)

Workspace: fevm-workshop-guy. Genie conversation: 1835980093459154. Branch: `fix/notebook-outputs` (from main `1d6feb3`).

Purpose: an evidence fix only. Nine notebooks had been committed with 0 cell outputs. Each was re-run interactively on serverless in the Git folder and committed with outputs. No pipeline logic, governance, threshold, data-model, or champion model changes.

## Before and after (GitHub copies)

| notebook | code cells | with output on main 1d6feb3 | with output on fix/notebook-outputs d960100 |
| --- | --- | --- | --- |
| fraud_model_training | 11 | 0 | 11 |
| fraud_batch_scoring | 8 | 0 | 8 |
| fraud_triage_agent | 7 | 0 | 7 |
| validation_notebooks/lakebase_sync_validation | 7 | 0 | 7 |
| validation_notebooks/lakebase_write_path_validation | 10 | 0 | 10 |
| validation_notebooks/lakebase_scores_validation | 6 | 0 | 6 |
| validation_notebooks/lakebase_fgac_validation | 8 | 0 | 8 |
| validation_notebooks/fgac_hardening | 10 | 0 | 10 |
| validation_notebooks/dashboard_validation | 15 | 0 | 15 |

Error outputs: 0 in every notebook. Not touched (already had outputs): card_transaction_bronze_generator (8/9), validation_notebooks/gold_feature_validation (4/4).

## Why the first push had no outputs

Commit `cca7f02` pushed the source edits but 0 outputs. Interactive run outputs are stored with the workspace notebook object, not in the Git folder's `.ipynb` file, so Git saw no output change. Commit `d960100` wrote the outputs into the files by exporting each notebook as Jupyter and importing it back over the same path (object IDs unchanged), the same method used in `b7b8d78` on 2026-10-16. The workspace setting `reposIpynbResultsExportPermissions` was not the cause and was not changed.

## Notebook edits (safety and evidence only)

* fraud_model_training: `REGISTER_MODEL = False` guard and `CHAMPION_RUN_ID`; last cell prints champion vs this run side by side.
* fraud_triage_agent: `REGISTER_AGENT = False`; removed `dbutils.notebook.exit` (it would have dropped later outputs).
* fgac_hardening: summary print in the empty last cell (check/verify only; no fix applied, job not re-run).
* dashboard_validation: `LOG_DATE = "2026-10-23"` so D.1 writes `logs/dashboard_dataset_results_2026-10-23.md` and the committed 2026-10-22 file is unchanged.

## Run timestamps (UTC)

| notebook | run |
| --- | --- |
| fraud_model_training | 2026-10-23 03:25:30 to 03:28:47 |
| fraud_batch_scoring | first pass from 2026-10-23 03:29:14 (write cell blocked); full re-run by the user 2026-10-24 00:21:06 to 00:23:38 |
| lakebase_sync_validation, lakebase_scores_validation, lakebase_write_path_validation, lakebase_fgac_validation, fgac_hardening | 2026-10-23 (scores validation re-run 2026-10-24 after the second sync) |
| fraud_triage_agent | 2026-10-23 23:25 |
| dashboard_validation | 2026-10-23 23:30:43 to 23:47:55 |

## Champion model check

fraud_risk_model @champion stays v1, run `d89beaca8f81447780da60ed2ea7c811`. Re-training run `5c12ba7b458f4794a37a50aee6d8845e` was not registered. Metrics are identical (max difference 0.0):

| metric | champion | re-run |
| --- | --- | --- |
| ROC-AUC | 0.8448 | 0.8448 |
| PR-AUC | 0.2808 | 0.2808 |
| block_threshold | 0.950267 | 0.950267 |
| review_threshold | 0.871416 | 0.871416 |
| cohort_amt_ratio_p90 | 0.5442 | 0.5442 |

fraud_triage_agent @champion is v2 (run `97bc6c9b4e654abab627cd25ee93fa53`, created about 2026-10-21 00:36 UTC, before this re-run). It still depends on the three UC functions. Nothing was registered in this re-run.

## Data refreshes

* scored_transactions rewritten by fraud_batch_scoring (Delta version 8, 2026-10-24 00:23:18). Same 464,632 rows and same scores; only `scored_at` changed (now 2026-10-24 00:22:56).
* Lakebase sync pipeline `f8690359-4bb1-45b9-8fdb-5bd892239db2`: update `77aed600-3257-4835-ae30-12fa4c8a2ff8` (2026-10-23 03:33) and update `7cd29431-4a45-414c-8745-4ddc84953595` (2026-10-24, after the rewrite). Both COMPLETED. After the second one, UC and Postgres both show 464,632 rows and max `scored_at` 2026-10-24 00:22:56.

## Cases

* TXN-0234209 returned its existing open case `2319d4b7-bea3-412b-ba6b-8325e1a7a71d` (auto_block); 1 open case after 2 requests.
* Live-read proof (dashboard_validation D.2): case `2c96d428-da99-49e5-b6ac-70ebb16e2ce5` on TXN-0112255, left open. ds_kpi_cases went from 220 visible / 8 open to 221 / 9 with no sync or job in between.
* lakebase_write_path_validation test case `018b3ed8-fae2-43ba-99d8-e50afea74fff` and its 50 benchmark cases were closed.

## Numbers that differ from earlier logs

| item | earlier | this run | reason |
| --- | --- | --- | --- |
| synced read p50 (lakebase_sync_validation) | 2.42 ms | 3.04 ms | normal variance |
| scores read p50 (lakebase_scores_validation) | 2.10 ms | 2.53 ms (3.63 ms in the first pass) | normal variance |
| case write p50 (lakebase_write_path_validation) | 33.21 ms | 39.66 ms | variance; more rows in cases tables |
| scored_at | 2026-10-21 02:36:46 | 2026-10-24 00:22:56 | scored_transactions rewritten; scores unchanged |
| cases visible to fraud_lead | earlier counts | 226 (220 in fraud_dash; 6 have amount > 10000) | cases added by validation runs |

## Known items (not fixed here)

* `explain_top_signals` errored for TXN-0112255 in the D.2 agent call ("Unknown format code 'f' for object of type 'str'"). The cell succeeded and the case was created; this is a tool bug to look at separately.
* lakebase_write_path_validation "invalid recommended_action" prints NO ERROR: the txn already has a case, so the idempotent create returns it before the check. Same as earlier runs.
* fe_bar_lakebase.cases.fraud_cases returns 0 rows through UC by design (RLS; the UC reader role has no policy).
