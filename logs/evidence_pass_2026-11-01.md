# Step 7 evidence pass (2026-11-01)

Genie conversation ID: 245211859776391 (Step 7 job 167137439226928, run 715334028805937, task `step_7`; completion pass in the same conversation)
Workspace: fevm-workshop-guy
Date: 2026-11-01
Branch: `step7/2026-11-01_fevm-workshop-guy_conv-245211859776391` (from main f905a98)
User: alex.owen@databricks.com (printed by `current_user()` in lineage_validation cell 1)

## 1. What happened in the job run

Job run 715334028805937 (task `step_7`, a Genie Code task) ended SUCCESS after 36.6 min (17:44 to 18:21 UTC). It wrote README.md, BUILD.md, prompts/, the `explain_top_signals` fix, logs/lineage_2026-11-01.md, the logs/dashboard_2026-10-22.md wording fix and validation_notebooks/lineage_validation.ipynb. It did not write this log and did not commit, push or merge. The completion pass below re-ran both notebooks interactively and finished the Git steps.

## 2. Run timestamps (UTC)

| Notebook | Object ID | Cells run | Start | Result |
|---|---|---|---|---|
| validation_notebooks/lineage_validation | 245211859776397 | 7 code cells, in order | 2026-11-01 19:04:38 (`run_at_utc` in cell 1) | 7/7 success, no safety-check blocks, no permission errors |
| fraud_triage_agent | 1507503687185883 | 7 code cells, in order, then new cell E.7 | 2026-11-01 ~19:07 (E.1 MLflow warning stamped 19:07:45) | 8/8 success, no safety-check blocks, no permission errors |

After the runs, both notebooks were exported as JUPYTER with `w.workspace.export` and imported back over the same path with `w.workspace.import_(format=JUPYTER, overwrite=True)`. Object IDs were unchanged (245211859776397, 1507503687185883). The `.ipynb` files on disk contain the 2026-11-01 19:0x outputs.

## 3. Notebook output counts (code cells / with output / error outputs)

Before = origin/main f905a98. After = branch working tree after the export/import.

| Notebook | Before | After | Change |
|---|---|---|---|
| card_transaction_bronze_generator | 9 / 8 / 0 | 9 / 8 / 0 | none (not re-run; the one cell without output is unchanged from main) |
| fraud_batch_scoring | 8 / 8 / 0 | 8 / 8 / 0 | none (not re-run) |
| fraud_model_training | 11 / 11 / 0 | 11 / 11 / 0 | none (not re-run) |
| fraud_triage_agent | 7 / 7 / 0 | 8 / 8 / 0 | re-run; added read-only cell E.7 (Part E verify) |
| validation_notebooks/dashboard_validation | 15 / 15 / 0 | 15 / 15 / 0 | none (not re-run) |
| validation_notebooks/fgac_hardening | 10 / 10 / 0 | 10 / 10 / 0 | none (not re-run) |
| validation_notebooks/gold_feature_validation | 4 / 4 / 0 | 4 / 4 / 0 | none (not re-run) |
| validation_notebooks/lakebase_fgac_validation | 8 / 8 / 0 | 8 / 8 / 0 | none (not re-run) |
| validation_notebooks/lakebase_scores_validation | 6 / 6 / 0 | 6 / 6 / 0 | none (not re-run) |
| validation_notebooks/lakebase_sync_validation | 7 / 7 / 0 | 7 / 7 / 0 | none (not re-run) |
| validation_notebooks/lakebase_write_path_validation | 10 / 10 / 0 | 10 / 10 / 0 | none (not re-run) |
| validation_notebooks/lineage_validation | new | 7 / 7 / 0 | new notebook |

Every count is the same as or higher than the baseline. 0 error outputs in all 12 notebooks.

## 4. Champion metric comparison

| Model | Alias | Expected (earlier logs) | Read on 2026-11-01 | Match |
|---|---|---|---|---|
| workshop_guy_catalog.fe_bar_a0.fraud_risk_model | @champion -> v1 | run d89beaca8f81447780da60ed2ea7c811, ROC-AUC 0.8448, PR-AUC 0.2808, block 0.950267, review 0.871416 | v1, run d89beaca8f81447780da60ed2ea7c811, test_roc_auc 0.8448, test_pr_auc 0.2808, block_threshold 0.9502674433961342, review_threshold 0.8714158290727556 (lineage_validation B.5) | yes |
| workshop_guy_catalog.fe_bar_a0.fraud_triage_agent | @champion -> v2 | run 97bc6c9b4e654abab627cd25ee93fa53 | v2, run 97bc6c9b4e654abab627cd25ee93fa53 (fraud_triage_agent cell D.3) | yes |

No model or agent was trained, logged or registered. `REGISTER_AGENT = False` in fraud_triage_agent; `REGISTER_MODEL = False` in fraud_model_training, which was not run. Agent v2 predates the 2026-10-21 hardening and this `explain_top_signals` fix, so the committed `fraud_triage_agent.py` is newer than the registered version. Re-registration still needs your approval. (Superseded the same day: the user approved it and v3 was registered; see section 12.)

## 5. Sync pipeline updates

None ran. Neither notebook writes `scored_transactions` (its writers in `system.access.table_lineage` are fraud_batch_scoring and job fe_bar_gold_to_lakebase only, latest 2026-10-24 00:23:18). The latest update of sync pipeline f8690359-4bb1-45b9-8fdb-5bd892239db2 is still 7cd29431-4a45-414c-8745-4ddc84953595 (COMPLETED, created 2026-10-24 00:25:45 UTC). All 4 synced tables report SYNCED_TABLE_ONLINE_NO_PENDING_UPDATE.

## 6. Case IDs created / closed

Created: none. Closed: none.

E.2 and E.3 asked the agent twice to open a case for TXN-0234209. Both times it returned the existing open case 2319d4b7-bea3-412b-ba6b-8325e1a7a71d (status open, queue auto_block, created_by fraud_triage_copilot:agent, db_inserted_by alex.owen@databricks.com). E.3 counted 1 open case for TXN-0234209 (expected 1). E.6: TXN-9999999 was reported as not found, and the approve-band block request for TXN-0278800 was refused. The E.5 cell is a static markdown table from the Step 5 test run and was not re-executed.

## 7. Step 1 conversation ID (Part A.3)

Result: **3458967129203277** (confirmed).

* Commit 1386cca (the PR #1 commit, merged as ca5a843) has `Genie Conversation ID: 3458967129203277` in its own message body (`git show -s 1386cca`).
* The transcript of conversation object 3458967129203277 ("FE Bar Data Generator Setup", in ~/.conversations) contains the `git merge --no-ff feature/card-transaction-bronze-generator` command, and its message has the same conversation ID.
* The transcript does not contain the literal hashes 1386cca or ca5a843. 1386cca is authored by aowen5000 and ca5a843 is the GitHub PR merge, so neither hash was printed inside the conversation.

## 8. Part E: explain_top_signals bug

Root cause: SHAP signals for categorical features (for example `risk_segment = 'high'`) carry a string `value`, and some numeric values are NULL (None). The old code applied numeric format specs (`f"{val:.1f}"`, `int(val)`, `:.4f`) directly to `value`. It raised `ValueError: Unknown format code 'f' for object of type 'str'` on strings and `TypeError: unsupported format string passed to NoneType.__format__` on None. TXN-0112255 failed because its third signal is `risk_segment = high`.

Diff summary (`fraud_triage_agent.py`, `explain_top_signals` only, +27/-13 lines): added `_num` (to float, or None for None/empty/non-numeric) and `_fmt` (numeric format spec, else the text value, `n/a` for None/empty). The sort key and every feature branch now go through these helpers. Query, tool signature, output shape and provenance envelope are unchanged.

Verification:

| Check | Method | Result |
|---|---|---|
| TXN-0112255 live | notebook cell E.7, tool called against fraud_gov.* as fraud_triage_agent | OK: is_new_device 1 (SHAP 1.9395), geo_distance_from_home 332.9 km (1.8503), risk_segment high (0.8605) |
| TXN-0234209 live | same cell | OK: is_new_device 2.5724, geo 450.6 km 1.8741, is_online 1.2001 (matches Step 4 SHAP values) |
| Agent end to end | E.1 trace tr-372bc4fc3a27c07127bdc96756ac3920 | 3 tool spans, all `agent_python:postgres:fraud_triage_agent`; no UC function tool called |
| Old vs new, offline replay | old function from origin/main and new from the branch, run on the same rows from `scored_transactions` joined to gold (UC), with formatting only and no Postgres | 24,906 review/block transactions: old code fails on 10,146 (both error types above), new code fails on 0 |

## 9. Lineage hops missing from system tables

13 of 19 expected hops are in `system.access.table_lineage` (18 edges in scope; 87 column-lineage rows for the governed columns). The 6 missing hops are filled with NEXT-BEST EVIDENCE in lineage_validation cell B.3 (see `logs/lineage_2026-11-01.md`):

* raw -> bronze (4): `/Volumes/workshop_guy_catalog/fe_bar_a0/staging/{transactions,customers,merchants,prior_fraud_cases}` -> the 4 bronze streaming tables. Evidence: the SDP pipeline source (read_files paths).
* gold -> Lakebase (2): `txn_features_gold` -> `fe_bar_lakebase.fraud.txn_features` and `customer_risk_profile_gold` -> `fe_bar_lakebase.fraud.customer_risk_profile`. Evidence: the synced-table specs (source table, PK, SNAPSHOT, pipeline f8690359).

## 10. Numbers that differ from earlier runs

| Number | Earlier | 2026-11-01 | Reason |
|---|---|---|---|
| fraud_triage_agent code cells | 7 | 8 | Added read-only cell E.7 to verify the Part E fix live |
| E.1 latency (TXN-0234209) | 44.1 s (Step 5), 17.2 s (origin/main outputs) | 16.0 s | LLM endpoint latency varies run to run; the tools did not change apart from the formatting fix |
| E.2 latency | 12.2 s (origin/main outputs) | 10.6 s | Same as above |
| BUILD.md Part E test size | "23/23 pass, old code fails on 9 of 23" (step_7 job draft) | 24,906 tested, 10,146 old failures, 0 new | The 23-transaction test could not be found or reproduced, so BUILD.md now cites the full replay above |

Lineage counts (18 edges, 13/19 hops, 87 column-lineage rows) and the model metrics match the step_7 job run's `logs/lineage_2026-11-01.md`.

## 11. Token scan

Patterns: `dapi[0-9a-f]{20,}`, `eyJ[A-Za-z0-9_-]{20,}`, `ghp_[A-Za-z0-9]{20,}`, `password=` followed by a value. Scanned the added lines of the staged diff (18 files) before the commit. Result: 0 matches. A loose scan for the bare strings `dapi`, `eyJ`, `ghp_` and `password=` finds 7 hits. All of them are the pattern names themselves (in the Step 7 prompt text and in this log), not values. Nothing was redacted.

## 12. Follow-up (2026-11-01): agent v3 registered, trace IDs corrected

Genie conversation ID: 1125672163420859. Workspace: fevm-workshop-guy. Branch: `step7-followup/2026-11-01_fevm-workshop-guy_conv-1125672163420859` from main 2181f41. The user approved registering a new version and moving @champion. No changes to pipelines, governance, thresholds, data, fraud_risk_model or the `fraud_triage_agent.py` logic. The agent was not deployed.

### Agent versions

| | Old | New |
|---|---|---|
| Version | v2 (kept, no alias, status READY) | **v3** (@champion) |
| Run | 97bc6c9b4e654abab627cd25ee93fa53 | d25dfe72e129478a8e17c0d6dbc7d433 (run name `fraud_triage_agent_v3_2026-11-01`) |
| Logged from | pre-2026-10-21 agent with UC-function tools | current `fraud_triage_agent.py` (Postgres-governed tools, `explain_top_signals` fix), plus `lakebase_cases.py` as a code path |
| Experiment | /Users/alex.owen@databricks.com/fe_bar_fraud_triage_agent | same |

Registered in fraud_triage_agent.ipynb cell D.3 with `REGISTER_AGENT = True` (2026-11-01 19:34 UTC). The cell output shows `BEFORE: @champion -> v2`, the run ID, `Created version '3'` and `AFTER: @champion moved v2 -> v3; v2 kept`. After the run, the source was set back to `REGISTER_AGENT = False` without re-running D.3, so the committed output is from the registration run.

Gate before `register_model`: the logged model has a signature and an input example, and `mlflow.models.predict(..., env_manager="uv")` built a fresh environment from `pip_requirements`, loaded the model and answered the input example ("Why was TXN-0234209 flagged?"). Result: `isolated uv validation: PASSED`.

### Declared resources

| Resource | Declared | Note |
|---|---|---|
| Serving endpoint `databricks-claude-sonnet-5-5` | yes, `DatabricksServingEndpoint` | the agent's LLM |
| Lakebase Postgres: project `fe-bar-fraud-analytics`, branch `production`, endpoint `primary`, database `fe_bar_db`, role `fraud_triage_agent` | **no (cannot be declared)** | `mlflow.models.resources.DatabricksLakebase` in MLflow 3.12.0 only takes `database_instance_name` (provisioned Lakebase). This is a Lakebase Autoscaling project and `w.database.list_database_instances()` returns none, so no valid value exists. Recorded as run tags `lakebase_endpoint`, `lakebase_database`, `pg_role` and `lakebase_resource_declared=false` |
| Deprecated UC functions (`get_transaction_risk`, `explain_top_signals`, `get_customer_history`) | no | not used by the agent since 2026-10-21 |

### D.4 verify (new cell in fraud_triage_agent.ipynb, 2026-11-01 19:36:48 UTC)

Loaded `models:/workshop_guy_catalog.fe_bar_a0.fraud_triage_agent@champion` (v3, run d25dfe72e129478a8e17c0d6dbc7d433). Asked it to explain each transaction only.

| Transaction | Trace | Tool spans (all `agent_python:postgres:fraud_triage_agent`, status OK) | Result |
|---|---|---|---|
| TXN-0234209 | tr-764034ca8a1e1ae9b19cbc35d413a50a | get_transaction_risk 373.7 ms, explain_top_signals 374.4 ms, get_customer_history 1779.1 ms | score 0.984, block, confidence medium (block_band precision 0.50, n=288) |
| TXN-0112255 | tr-a54c80e15e88d7fb7a5e3464f173695f | get_transaction_risk 19.3 ms, explain_top_signals 31.2 ms, get_customer_history 1778.7 ms | score 0.992, block; signals new device, 332.9 km, risk_segment high (the Part E case) |

6 tool spans, 0 errors, `create_fraud_case` not called. Case sets before and after were the same: TXN-0234209 -> 2319d4b7-bea3-412b-ba6b-8325e1a7a71d, TXN-0112255 -> 2c96d428-da99-49e5-b6ac-70ebb16e2ce5. No cases created or closed.

### Trace ID corrections

Every `tr-<32 hex>` ID in README.md, BUILD.md and logs/ was checked against committed notebook outputs and committed trace JSON. Results:

| Trace ID | Cited in | Status before | Fix |
|---|---|---|---|
| tr-9047494d... (stale; full ID removed from the repo) | README end-to-end trace, hop 7 | Not in any committed output. It is the step_7 job run's E.1 trace (MLflow, 2026-11-01 18:02 UTC); that output was replaced by the interactive re-run | Replaced with tr-372bc4fc3a27c07127bdc96756ac3920 (committed E.1 output). E.1 was not re-run in this follow-up |
| tr-a378f1a1b9d34fc7e7e7bf911599b31b | README live-read proof; logs/dashboard_2026-10-22.md | Not committed (interactive output lost, as the log already said) | Exported from MLflow to `logs/trace_evidence_2026-11-01.json`; README now points there |
| tr-6659ce2b852915f489c9add9eef92cbd | logs/dashboard_2026-10-22.md; logs/dashboard_validation_run_659281894932228.md | Only in the Markdown export of the job-run output (not in an .ipynb or JSON) | Exported to `logs/trace_evidence_2026-11-01.json` |
| tr-69e222b86590f5a587f13d5dc3a6cb69 | logs/fgac_hardening_2026-10-21.md | Session dry run, never in a notebook | Exported to `logs/trace_evidence_2026-11-01.json` |
| tr-f7e09df1c76848b6ffa8e5ca07e3fe95 | logs/fgac_hardening_2026-10-21.md | Log said "printed in fraud_triage_agent.ipynb", but later re-runs replaced that output | Wording corrected; exported to `logs/trace_evidence_2026-11-01.json` |
| tr-d1891643..., tr-2fb3e5d6..., tr-135952fd..., tr-ceb9e85f..., tr-e9ec43cd... | logs/agent_trace_2026-10-21.json, logs/agent_triage_2026-10-21.md | in committed trace JSON | none needed |
| tr-372bc4fc3a27c07127bdc96756ac3920 | README hop 7; this log | in committed fraud_triage_agent.ipynb E.1 output | none needed |

Finding while exporting: in both Step 6 D.2 traces (tr-a378f1a1..., tr-6659ce2b...) `explain_top_signals` has two ERROR spans with "Unknown format code 'f' for object of type 'str'". That is the Part E bug, before the fix. The agent still opened the cases, but those two explanations were produced without the signal tool. The trace state is OK because the agent recovered.
