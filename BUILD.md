# BUILD: how FE-BAR-2026 was built

I chose the customer problem, the architecture and the governance model, and wrote and reviewed every prompt. Genie Code implemented each step from those prompts in workspace `fevm-workshop-guy`, and I reviewed the outputs and made the calls in [DECISIONS.md](DECISIONS.md). I wrote the prompts with help from Claude. They are in `prompts/` (index: [docs/PROMPTS.md](docs/PROMPTS.md)).

## Tools and skills

* **Genie Code** built every object in this repo and workspace.
* **Skills.** From Step 2 (gold) on, every session began by confirming access to the Genie Code skills installed by `/Workspace/Users/alex.owen@databricks.com/Install-Genie-Skills-Notebook/genie_code_agent_Skills_Install`. That notebook installs 31 skill folders under `~/.assistant/skills`. The relevant skill was loaded before each task.
* **Platform.** Spark Declarative Pipelines with Auto Loader, Unity Catalog, Lakebase, MLflow and UC models, Foundation Model API (`databricks-claude-sonnet-5-5`), Genie Agent, Databricks Apps, AI/BI dashboard, Lakeflow Jobs, serverless.
* **Guardrails in the prompts.** If a permission or access error came up, Genie Code was to stop and flag it rather than work around it. Notebooks had to be committed with outputs. Evidence had to be text only.
* **Git.** Each step ran on its own branch in the Git folder `/Workspace/Users/alex.owen@databricks.com/FE-BAR-2026-repo` (remote `https://github.com/aowen5000/FE-BAR-2026`). Branches were merged into main with `--no-ff` (Step 1 used GitHub PR #1). The commit message carried the Genie conversation ID, the workspace and the date. Wrong or missing metadata was corrected in a follow-up commit, not by rewriting history (`logs/commit_metadata_corrections.md`, `docs/CONVERSATION_IDS.md`). Two author identities appear in history, both mine; see Commit identities in README.md.

## Per-step table

Merges from `git log --merges --first-parent main`; ID notes in `docs/CONVERSATION_IDS.md`.

| Step | Branch | Merge | Conversation | Date (UTC) | What was built | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `feature/card-transaction-bronze-generator` | ca5a843 (PR #1); c287981 | 3458967129203277 | 2026-10-08, 2026-10-15 | Synthetic generator; JSON with 15% DQ errors | `card_transaction_bronze_generator.ipynb` |
| 2 | `feature/bronze-silver-autoloader-pipeline`, `feature/consolidate-pipeline-to-sql-notebook` | 69c7546, 563f534 | 2172058462486781 | 2026-10-15 | SDP pipeline c0db28b8: bronze STs, silver MVs with expectations, row filter, mask | `logs/update_60f6d1de_full_refresh_2026-10-15.md` |
| 2 (gold) | `feature/gold-feature-layer`, `feature/rename-pipeline-and-fix-outputs`, `feature/commit-notebook-outputs` | e6e20bc, 1b646df, 63aa15f | 2172058462486781 | 2026-10-16 | Gold MVs | `gold_feature_layer.sql`, `logs/update_c9e70e47_gold_refresh_2026-10-16.md` |
| 3 | `feat/lakebase-sync-write-path-2026-10-17` | f26c2d6 | 3367633421784666 | 2026-10-17 | Lakebase project, synced tables, `cases` schema, job | `logs/lakebase_sync_2026-10-17.md`, `logs/lakebase_write_path_2026-10-17.md` |
| 4 | `feature/ml-batch-scoring` | 9010627 | 2565515039400048 | 2026-10-20 | LightGBM model, `scored_transactions`, `fraud.txn_risk_current` | `logs/ml_training_2026-10-20.md`, `logs/batch_scoring_2026-10-20.md` |
| 5 | `feature/fraud-triage-agent`, `feature/fgac-hardening`, `feature/validation-notebooks-folder` | 03402cb, 9873b5d, 2175fc5 | 1507503687185838 | 2026-10-21 | Postgres FGAC, Fraud Triage Copilot, hardening pass | `logs/lakebase_fgac_2026-10-21.md`, `logs/fgac_hardening_2026-10-21.md` |
| 6 | `feature/fraud-ops-dashboard`, `step6/2026-10-22_fevm-workshop-guy_conv-1835980093459154` | ee35a48, 968b794 | 1835980093459154 | 2026-10-23 | `fraud_dash` views, AI/BI dashboard, live-read proof | `logs/dashboard_2026-10-22.md` |
| 6 (outputs) | `fix/notebook-outputs` | f905a98 | 1835980093459154 (session 2460977471802157) | 2026-10-24 | Notebook outputs re-run | `logs/notebook_outputs_rerun_2026-10-23.md` |
| 7 | `step7/2026-11-01_fevm-workshop-guy_conv-245211859776391` | 2181f41 | 245211859776391 | 2026-11-01 | README, BUILD, prompts/, lineage evidence | `logs/evidence_pass_2026-11-01.md`, `logs/lineage_2026-11-01.md` |
| 7 (follow-up) | `step7-followup/2026-11-01_fevm-workshop-guy_conv-1125672163420859` | 549fac2 | 1125672163420859 | 2026-11-01 | Agent @champion v3, trace ID fixes | `logs/trace_evidence_2026-11-01.json` |
| 8 | `step8/2026-11-03_fevm-workshop-guy_conv-2326365276521178` | 8c5da6d | 2326365276521178 | 2026-11-03 | Genie Agent, 11/11 benchmark, `triage_queue` fix | `logs/genie_agent_2026-11-03.md` |
| 8b | `step8b/2026-11-04_fevm-workshop-guy_conv-2326365276521178` | a14d8c0 | 2326365276521178 | 2026-11-04 | Gold row filter and mask, `non_pii` access, Genie round 2 | `logs/gold_governance_2026-11-04.md`, `validation_notebooks/gold_governance_hardening.ipynb` |
| 8c | `step8c/2026-11-04_fevm-workshop-guy_conv-2326365276521178` | 346289b | 2326365276521178 | 2026-11-04 | `account users` narrowed to least privilege on `fe_bar_a0` | `validation_notebooks/catalog_grant_narrowing.ipynb` |
| 8d | `step8d/2026-11-04_fevm-workshop-guy_conv-2326365276521178` | 894e41a | 2326365276521178 | 2026-11-04 | `customer_risk_profile_gold` revoke recorded | `logs/gold_governance_2026-11-04.md` |
| 8e | `step8e/2026-11-05_fevm-workshop-guy_conv-2326365276521178` | e54d5c8 | 2326365276521178 | 2026-11-05 | non_pii benchmark run, 11/11 | `genie_agent_benchmark_evidence_logs/` |
| 9 | `step9/2026-11-04_fevm-workshop-guy_conv-1085628541759563` | d54f358 | 1085628541759563 | 2026-11-06 | Databricks App `fe-bar-fraud-triage` | `logs/app_2026-11-04.md`, `validation_notebooks/app_validation.ipynb` |
| docs | `docs/2026-11-06_fevm-workshop-guy_conv-1883459888084279` | f6d6fd4 | 1883459888084279 | 2026-11-06 | Commit identities note | `README.md` |
| 10 | `step10/2026-11-06_fevm-workshop-guy_conv-1883459888084300` | in `logs/final_verification_2026-11-06.md` | 1883459888084300 | 2026-11-06 | Business value, job run, docs rewrite | `logs/business_value_2026-11-06.md`, `logs/job_fe_bar_gold_to_lakebase_run_1059811930012881_2026-11-06.md` |

## Issues hit and how they were resolved

* **Empty notebook outputs, twice.** Outputs live in the workspace object, not the `.ipynb` Git sees. Fix: export as JUPYTER and import over the same path. `logs/notebook_outputs_rerun_2026-10-23.md`.
* **Wrong or missing commit metadata** (dae23d6, c3d825c, 7349425): corrected in a follow-up commit. `logs/commit_metadata_corrections.md`.
* **Conversation IDs reused across sessions, and merge 346289b says "Merges step8b" for step8c.** Documented, not rewritten. `docs/CONVERSATION_IDS.md`.
* **`explain_top_signals` format error** on string and None values. Fixed with `_num` / `_fmt` helpers. Offline replay: the old code fails on 10,146 of 24,906 review/block transactions, the fixed code on 0. `logs/evidence_pass_2026-11-01.md`.
* **Single-machine SHAP scoring timed out.** Distributed with `mapInPandas` (64 partitions); max diff vs the registered pyfunc 0.0. `logs/batch_scoring_2026-10-20.md`.
* **Case history empty through UC, and agent attribution could be spoofed.** Tools moved agent-side; `db_inserted_by` checked in the INSERT policies. `logs/fgac_hardening_2026-10-21.md` Items 5 and 7.
* **Step 1: GitHub credential lacked repo scope; schema REVOKEs were safety-blocked.** I fixed the credential. The REVOKEs were flagged, not worked around.
* **Safety check blocked the `INSERT OVERWRITE` cell in the outputs re-run.** I re-ran the notebook on 2026-10-24. `logs/notebook_outputs_rerun_2026-10-23.md` "Run timestamps".
* **Step 8: job run 273696236528085 failed at `lakebase_sync_refresh`** (`ROW_LEVEL_SECURITY_FEATURE_NOT_SUPPORTED.TIME_TRAVEL`, row filter on `scored_transactions`). I dropped that filter (option B). The job is green again in run 1059811930012881. `logs/gold_governance_2026-11-04.md`; `logs/job_fe_bar_gold_to_lakebase_run_1059811930012881_2026-11-06.md`.
* **Step 9: the App health endpoint needs OAuth from a notebook.** D.2 recorded as not possible. `logs/app_2026-11-04.md`.
* **Step 10: `databricks workspace delete` was blocked by the safety guardrail.** README.md and BUILD.md were edited in place instead.

## What I would do next

* **Vector Search grounding** over `fact_prior_fraud_cases_silver` and case notes, so the agent cites similar past cases.
* **Real-time serving** of `fraud_risk_model` for online scoring of new transactions.
* **`mlflow.genai.evaluate`** on a labelled set of flagged transactions, with groundedness and correct-action judges.
* **Drift monitoring** on `txn_features_gold` and `scored_transactions`, feeding retraining.
* **Per-user OBO auth for the App**, so Postgres writes, Genie questions and warehouse queries carry the analyst's identity.
* **A Metric View for the fraud KPIs** (fraud $ caught, false positive rate, analyst hours), with one shared definition.
