# FE-BAR-2026

This is a fraud risk build for a regional card issuer, built in Databricks workspace `fevm-workshop-guy`. It uses 100% synthetic data. Everything in this repo is plain text: notebooks are committed with their cell outputs, and logs are Markdown or JSON. How the repo was built (AI-assisted workflow, prompts, key decisions, issues) is in [BUILD.md](BUILD.md).

## Overview

The build serves two personas: the **Head of Fraud Risk Ops**, who watches exposure, model performance and case volume, and the **Fraud Analyst**, who works a triage queue and opens cases. It has five layers that feed each other:

1. **Lakehouse data.** Synthetic card data (customers, merchants, transactions, prior fraud cases, with a seeded high-risk cohort) lands as JSON in a UC volume. An SDP pipeline turns it into bronze, then silver (UC row filter and column mask), then gold features.
2. **Lakebase.** Gold features and scores sync to Lakebase Postgres as SNAPSHOT synced tables. Native OLTP case tables are added alongside them, and Postgres FGAC is applied.
3. **ML batch scoring.** A LightGBM model in UC scores every transaction with the top 3 SHAP signals.
4. **Fraud Triage Copilot.** A tool-calling agent explains a flagged transaction and opens a case in Lakebase under its own governed Postgres role.
5. **Fraud Ops dashboard.** An AI/BI dashboard reads live from Lakebase, so a case the agent writes shows up with no sync in between.

Layer numbers 3 to 5 are the ones used in the step prompts. Layers 1 and 2 are grouped here as Steps 1 and 2 (data and pipeline) and Step 3 (Lakebase).

## Architecture

```
 Synthetic generator (card_transaction_bronze_generator.ipynb)
   | JSON, ~15% DQ errors
   v
 /Volumes/workshop_guy_catalog/fe_bar_a0/staging/{customers,merchants,transactions,prior_fraud_cases}/
   | Auto Loader (read_files)
   v
 SDP pipeline c0db28b8  ("FE BAR Bronze Silver AutoLoader Pipeline.sql" + gold_feature_layer.sql)
   bronze STs: dim_customer_bronze, dim_merchant_bronze, fact_transactions_bronze, fact_prior_fraud_cases_bronze
   silver MVs: dim_customer_silver [MASK avg_monthly_spend], dim_merchant_silver,
               fact_transactions_silver [ROW FILTER amount > 10000], fact_prior_fraud_cases_silver
   gold MVs:   txn_features_gold, customer_risk_profile_gold
   |                                   |
   | fraud_model_training -> UC model  | SNAPSHOT synced tables (sync pipeline f8690359)
   | fraud_risk_model@champion v1      v
   v                                  Lakebase project fe-bar-fraud-analytics / branch production / db fe_bar_db
 fraud_batch_scoring                   (UC catalog fe_bar_lakebase)
   -> scored_transactions  ---sync--->  fraud.txn_features, fraud.customer_risk_profile,
   -> risk_score_calibration --sync-->  fraud.txn_risk_current, fraud.risk_score_calibration   (read-only copies)
                                         |
                                         v  security_barrier views, pg_has_role(fraud_pii)
                                        fraud_gov.*  (row rule amount > 10000, column rule amt_to_monthly_spend)
                                         |                         |
   Fraud Triage Copilot (fraud_triage_agent.py)                    |
   SET ROLE fraud_triage_agent: reads fraud_gov.*,                 |
   writes cases.fraud_cases / cases.case_actions (FORCE RLS) ------+
                                         |                         |
                                         v                         v
                                        fraud_dash.* views (owned by fraud_lead, non-pii safe)
                                         | UC reader role databricks_reader_17063
                                         v
                     AI/BI dashboard "FE Bar Fraud Ops: Triage & Action" (warehouse 9bbc027402111984)

 Job fe_bar_gold_to_lakebase (1115396029932218): gold_pipeline_refresh -> batch_scoring -> lakebase_sync_refresh
```

## Layout

* Repo root: pipeline, model, agent and Lakebase source (notebooks, `.py` modules, `.sql` DDL)
* `validation_notebooks/`: check and verify notebooks with committed outputs
  * `gold_feature_validation`: gold feature layer checks
  * `lakebase_sync_validation`: gold to Lakebase synced tables
  * `lakebase_write_path_validation`: `cases` schema write path (`lakebase_cases.py`)
  * `lakebase_scores_validation`: `fraud.txn_risk_current` read path and latency
  * `lakebase_fgac_validation`: Postgres roles, `fraud_gov` views, RLS
  * `fgac_hardening`: Step 5 hardening pass, items 1 to 8
  * `dashboard_validation`: Step 6 dashboard dataset latency, FGAC deny tests, live-read proof, end-to-end trace
  * `lineage_validation`: Step 7 table, column and model lineage from `system.access.*`
  * `genie_agent_validation`: Step 8 Genie Agent pre-flight, governance check, creation, export, 11-question benchmark (Conversation API + native eval)
* `dashboards/`: exported Lakeview dashboard definitions
  * `fe_bar_fraud_ops.lvdash.json`: Fraud Ops triage & action dashboard
* `genie/`: exported Genie Agent (Genie space) definitions
  * `fraud_risk_ops_genie.json`: FE Bar Fraud Risk Ops space (serialized space: sources, column configs, joins, snippets, examples, benchmarks)
* `logs/`: run logs and evidence
* `prompts/`: the opening user prompt of each Genie Code conversation, copied verbatim (see BUILD.md)
* `BUILD.md`: AI-assisted workflow, per-step table, key decisions, issues

Validation notebooks import repo modules (for example `lakebase_cases`) from the repo root, one level above `validation_notebooks/`.

## Resource inventory

| Kind | Name | ID / detail |
| --- | --- | --- |
| UC catalog / schema | `workshop_guy_catalog.fe_bar_a0` | serverless everywhere |
| UC volume | `workshop_guy_catalog.fe_bar_a0.staging` | raw JSON: customers/, merchants/, transactions/, prior_fraud_cases/ |
| Bronze streaming tables | `dim_customer_bronze`, `dim_merchant_bronze`, `fact_transactions_bronze`, `fact_prior_fraud_cases_bronze` | in fe_bar_a0 |
| Silver MVs | `dim_customer_silver`, `dim_merchant_silver`, `fact_transactions_silver`, `fact_prior_fraud_cases_silver` | in fe_bar_a0 |
| UC row filter / column mask | `filter_high_amount_txns` on `fact_transactions_silver.amount`; `mask_avg_monthly_spend` on `dim_customer_silver.avg_monthly_spend` | full access only for UC group `pii` |
| Gold MVs | `txn_features_gold`, `customer_risk_profile_gold` | in fe_bar_a0 |
| Scored tables | `scored_transactions` (464,632 rows, PK txn_id), `risk_score_calibration` | in fe_bar_a0 |
| UC functions (deprecated) | `get_transaction_risk`, `explain_top_signals`, `get_customer_history` | `agent_tools.sql`; not registered with the agent since 2026-10-21 |
| SDP pipeline | FE BAR Bronze Silver AutoLoader Pipeline | `c0db28b8-dbd2-432d-99cf-4ea2aea60274` |
| Lakebase sync pipeline | SNAPSHOT synced tables | `f8690359-4bb1-45b9-8fdb-5bd892239db2` |
| Job | `fe_bar_gold_to_lakebase` | `1115396029932218`: gold_pipeline_refresh -> batch_scoring -> lakebase_sync_refresh |
| Lakebase | project `fe-bar-fraud-analytics`, branch `production`, endpoint `primary`, database `fe_bar_db` | UC catalog `fe_bar_lakebase` |
| Lakebase schemas | `fraud` (synced, read-only), `fraud_gov` (governed views), `cases` (native OLTP: `fraud_cases`, `case_actions`), `fraud_dash` (dashboard views) | |
| Postgres roles | `fraud_pii`, `fraud_analyst`, `fraud_lead`, `fraud_triage_agent` (NOLOGIN group roles); UC reader `databricks_reader_17063` | `lakebase_fgac.sql`, `lakebase_fgac_hardening.sql` |
| Model | `workshop_guy_catalog.fe_bar_a0.fraud_risk_model` @champion = v1 | run `d89beaca8f81447780da60ed2ea7c811`, experiment `/Users/alex.owen@databricks.com/fe_bar_fraud_risk_model` |
| Agent | `workshop_guy_catalog.fe_bar_a0.fraud_triage_agent` @champion = v3 (2026-11-01) | run `d25dfe72e129478a8e17c0d6dbc7d433`, experiment `/Users/alex.owen@databricks.com/fe_bar_fraud_triage_agent`; logged from the current `fraud_triage_agent.py` with `lakebase_cases.py` as a code path. Declared resources: serving endpoint `databricks-claude-sonnet-5-5`. Uses, not declared: Lakebase Postgres `fe_bar_db` on project `fe-bar-fraud-analytics`, branch `production`, endpoint `primary`, role `fraud_triage_agent` (see Known limitations). No UC functions. Registered, not deployed. v2 (run `97bc6c9b4e654abab627cd25ee93fa53`, pre-hardening UC-function tools) is kept without an alias |
| Dashboard | FE Bar Fraud Ops: Triage & Action | `01f1ce7f835a1e81b05ebb664bf0994c`, warehouse `9bbc027402111984`, definition `dashboards/fe_bar_fraud_ops.lvdash.json` |
| Genie Agent (Genie space) | FE Bar Fraud Risk Ops | `01f1d7b464d510b9aa6cde48300787ca`, warehouse `9bbc027402111984`, folder `/Users/alex.owen@databricks.com/FE Bar Genie`, definition `genie/fraud_risk_ops_genie.json`. Governed sources only: `fe_bar_lakebase.fraud_dash.{triage_queue, case_summary, case_actions_daily, exposure, baseline_comparison, score_distribution}` and `fe_bar_a0.risk_score_calibration`. Owner-only (no CAN_RUN grants). Evidence `logs/genie_agent_2026-11-03.md` |

## How to run

Prerequisites:

* Membership in the UC account group `pii`. Training and scoring stop if `is_account_group_member('pii')` is false, because the row filter and mask would silently remove the high-amount signal.
* A Postgres role with superuser-level rights in `fe_bar_db` (databricks_superuser with BYPASSRLS) for the DDL and FGAC setup.
* Serverless notebook compute and the serverless SQL warehouse `9bbc027402111984`.

Order:

| # | What | File | Re-run behavior |
| --- | --- | --- | --- |
| 1 | Generate synthetic JSON | `card_transaction_bronze_generator.ipynb` | Overwrites the JSON files in the staging volume (`mode("overwrite")`) |
| 2 | SDP pipeline c0db28b8 | `FE BAR Bronze Silver AutoLoader Pipeline.sql`, `gold_feature_layer.sql` | A refresh recomputes the MVs. A full refresh also reprocesses bronze |
| 3 | Train the model | `fraud_model_training.ipynb` | Safe. `REGISTER_MODEL = False` logs a new MLflow run only and does not move @champion |
| 4 | Batch scoring | `fraud_batch_scoring.ipynb` | **Overwrites** `scored_transactions` |
| 5 | Refresh and sync | job `fe_bar_gold_to_lakebase`, or the sync pipeline f8690359 alone | Refreshes gold, **overwrites** scores, and re-snapshots the synced tables |
| 6 | Lakebase DDL and FGAC | `lakebase_cases_ddl.sql`, `lakebase_fgac.sql`, `lakebase_fgac_hardening.sql`, `lakebase_dashboard.sql` | Written to be idempotent |
| 7 | UC tools (deprecated) | `agent_tools.sql` | `CREATE OR REPLACE`. The agent no longer uses them |
| 8 | Agent demo | `fraud_triage_agent.ipynb` (`fraud_triage_agent.py`, `lakebase_cases.py`) | Reuses the open case for TXN-0234209 (idempotent). `REGISTER_AGENT = False` (D.3 output shows the one-time v3 registration). D.4 loads @champion and explains TXN-0234209 and TXN-0112255 without opening cases |
| 9 | Dashboard | import `dashboards/fe_bar_fraud_ops.lvdash.json`, set warehouse 9bbc027402111984, publish with embedded credentials | |

Validation notebooks in `validation_notebooks/` are read-only, with these exceptions. `lakebase_write_path_validation`, `lakebase_fgac_validation` and `fgac_hardening` create test cases and close them. `dashboard_validation` D.2 opens one new live-proof case per run and leaves it open by design.

## Evidence index (Submission Checklist hard gates)

| Hard gate | Evidence (committed files) | Headline number |
| --- | --- | --- |
| All five layers functional | L1: `card_transaction_bronze_generator.ipynb`, `logs/update_60f6d1de_full_refresh_2026-10-15.md`, `logs/update_c9e70e47_gold_refresh_2026-10-16.md`, `validation_notebooks/gold_feature_validation.ipynb`. L2: `logs/lakebase_sync_2026-10-17.md`, `logs/lakebase_write_path_2026-10-17.md`. L3: `fraud_model_training.ipynb`, `fraud_batch_scoring.ipynb`, `logs/ml_training_2026-10-20.md`. L4: `fraud_triage_agent.ipynb`, `logs/agent_triage_2026-10-21.md`. L5: `validation_notebooks/dashboard_validation.ipynb`, `logs/dashboard_2026-10-22.md` | 464,632 gold rows, all scored; ROC-AUC 0.8448; agent explains and opens case 2319d4b7; 10 dashboard datasets run on the warehouse |
| One connected journey | "End-to-end trace: TXN-0234209" below; `logs/lineage_2026-11-01.md` | 9 hops, each with committed text evidence; 13/19 lineage hops in system tables and 6 filled with labelled next-best evidence |
| Proof it ran | Every `.ipynb` is committed with outputs (see `logs/evidence_pass_2026-11-01.md` for counts); pipeline and job run logs in `logs/` | 12 notebooks, every one with outputs and 0 error outputs |
| Lakebase synced tables match gold | `validation_notebooks/lakebase_sync_validation.ipynb`, `validation_notebooks/lakebase_scores_validation.ipynb`, `logs/lakebase_scores_sync_2026-10-20.md`, `logs/fgac_hardening_2026-10-21.md` Item 3 | UC 464,632 = Postgres 464,632 (txn_risk_current, txn_features); 9,289 = 9,289 (customer_risk_profile) |
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
* **Case IDs.** TXN-0234209 maps to `2319d4b7-bea3-412b-ba6b-8325e1a7a71d` (open, auto_block). Live-read proofs: `030dc7fb-3284-4cc2-9264-06b7de57c2cb` (TXN-0350980), `c2b2ec3a-a1a7-444f-a1c8-969af362c0ee` (TXN-0197951, job run 659281894932228) and `2c96d428-da99-49e5-b6ac-70ebb16e2ce5` (TXN-0112255, committed notebook run).
* **Dashboard live read.** The agent opened case 030dc7fb. With no sync or job in between, the dashboard KPI query went from cases_created_today 0 / open_cases 6 / visible_cases 164 (01:45:19 UTC) to 1 / 7 / 165 (01:45:41 UTC) on 2026-10-23.

## End-to-end trace: TXN-0234209

TXN-0234209 is the seeded-cohort transaction traced through every step: CUST-08669, $323.96, amt_to_monthly_spend 0.7825, cross-border, new device, is_fraud = true. The selection rule is in `logs/batch_scoring_2026-10-20.md`. "Code cell N" counts code cells only, top to bottom.

| # | Hop | Evidence (committed file and cell/section) | What it shows |
| --- | --- | --- | --- |
| 1 | raw volume / bronze | `validation_notebooks/dashboard_validation.ipynb` code cell 14 "D.3 End-to-end trace", journey table row "raw/bronze"; `logs/lineage_2026-11-01.md` section 2(a) | 2 bronze rows for TXN-0234209: the original plus an injected duplicate. Bronze reads `/Volumes/.../staging/transactions/` |
| 2 | silver | same cell, row "silver"; `logs/lineage_2026-11-01.md` section 1, hop 2 | 1 row after dedup; edge fact_transactions_bronze -> fact_transactions_silver (pipeline) |
| 3 | gold features | same cell, row "gold features"; `fraud_batch_scoring.ipynb` code cell 8 "Trace one high-risk seeded-cohort transaction" | 1 row in txn_features_gold; amt_to_monthly_spend 0.7824742766049949, is_cross_border 1, is_new_device 1 |
| 4 | score and SHAP signals | `fraud_batch_scoring.ipynb` code cell 8; `logs/batch_scoring_2026-10-20.md` "Traced seeded-cohort transaction" | risk_score 0.9844108757126732, block; is_new_device +2.5724, geo_distance_from_home 450.63 +1.8741, is_online +1.2001 |
| 5 | scored_transactions | `fraud_batch_scoring.ipynb` code cell 8 (reads the written table); `logs/notebook_outputs_rerun_2026-10-23.md` "Data refreshes" | model_version 1, scored_at 2026-10-24 00:22:56 (scores unchanged by re-runs) |
| 6 | Lakebase fraud.txn_risk_current | `validation_notebooks/lakebase_scores_validation.ipynb` code cell 4 "Traced transaction: UC vs Postgres"; `logs/lakebase_scores_sync_2026-10-20.md` "Traced transaction TXN-0234209"; `dashboard_validation.ipynb` code cell 14 (fraud_gov.txn_risk_current row) | UC = Postgres for risk_score, recommended_action, model_version (all True) |
| 7 | agent explanation and trace | `fraud_triage_agent.ipynb` code cell 3 "E.1: Explain - TXN-0234209 (+ trace span table)", re-run 2026-11-01; `logs/agent_triage_2026-10-21.md`; `logs/agent_trace_2026-10-21.json` | Trace tr-372bc4fc3a27c07127bdc96756ac3920: get_transaction_risk, explain_top_signals, get_customer_history, all `agent_python:postgres:fraud_triage_agent`, no tool errors; confidence medium (block_band precision 0.50, n=288) |
| 8 | case in cases.fraud_cases and its round-trip read | `fraud_triage_agent.ipynb` code cells 4-5 (E.2, E.3); `dashboard_validation.ipynb` code cell 4 "A.3 Cases in Postgres as fraud_lead"; `logs/agent_case_roundtrip_2026-10-21.md` | Case 2319d4b7-bea3-412b-ba6b-8325e1a7a71d, open, auto_block, created_by fraud_triage_copilot:agent, db_inserted_by alex.owen@databricks.com; read back as fraud_lead; 1 open case after 2 "open a case" requests |
| 9 | dashboard dataset | `dashboard_validation.ipynb` code cell 10 "B.3" (PASS) and code cell 14 (ds_triage with the txn_id filter) | ds_triage row: case 2319d4b7, open, auto_block, risk_rank 762; fraud_dash.case_summary shows the same case |

Gaps, stated honestly:

* Hops 1 and 2 show the bronze and silver row **counts** for TXN-0234209 (2 and 1), not the row contents.
* The raw JSON record in the volume is not printed anywhere in the repo. The volume -> bronze edge is supported by the pipeline source path (`logs/lineage_2026-11-01.md` section 2(a)), not by `system.access.table_lineage`.

**Live-read proof, case 030dc7fb** (`logs/dashboard_2026-10-22.md` "Live-Read Proof (D.2)"). On 2026-10-23 the agent was invoked once for TXN-0350980 and opened case 030dc7fb-3284-4cc2-9264-06b7de57c2cb (trace tr-a378f1a1b9d34fc7e7e7bf911599b31b; the interactive output was lost, so the trace is exported from MLflow to `logs/trace_evidence_2026-11-01.json`). ds_kpi_cases read cases_created_today 0 / open_cases 6 / visible_cases 164 before (01:45:19 UTC) and 1 / 7 / 165 after (01:45:41 UTC). No sync or job ran in between. The case row is also in `logs/dashboard_dataset_results_2026-10-22.md` (ds_triage and ds_recent_cases, created 2026-10-23T01:45:33.754Z).

The notebook cell output of that interactive run was not preserved (see "Evidence status" in the same log). The same proof was repeated twice with outputs kept:

* Job run 659281894932228: case c2b2ec3a, 1 / 7 / 165 to 2 / 8 / 166 (`logs/dashboard_validation_run_659281894932228.md`).
* The committed `dashboard_validation.ipynb` code cell 13 "D.2": case 2c96d428, visible/open 220 / 8 to 221 / 9 (`logs/notebook_outputs_rerun_2026-10-23.md`).

## Known limitations

* Lakebase synced tables are owned by the sync pipeline's writer role, so they cannot carry Postgres RLS. UC row filters and masks are not propagated to them either. Governance is applied through the `fraud_gov` security_barrier views, and no governed role has a grant on `fraud.*`. A stricter alternative (sync a pre-filtered UC view) is documented in `logs/agent_governance_2026-10-21.md` Item 4.
* UC queries on `fe_bar_lakebase` run in Postgres as `databricks_reader_17063`, which is not identity-aware. Through UC, `fraud_gov` always returns the non-pii result and `cases.*` returns 0 rows. The dashboard therefore shows only non-pii-safe data, from `fraud_dash`.
* Membership in the `fraud_pii` Postgres role is managed manually. `pii_role_sync.py` only prints a plan (dry run by default).
* Both the agent and the notebooks connect to Postgres as alex.owen, so `db_inserted_by` does not yet tell the agent apart from a human. In production the agent should connect as its own service principal.
* The agent is registered in UC (@champion v3) but not deployed. Its Lakebase dependency is not declared as an MLflow resource: `mlflow.models.resources.DatabricksLakebase` (MLflow 3.12) only accepts a provisioned `database_instance_name`, and the Lakebase Autoscaling project `fe-bar-fraud-analytics` has no database instance. A deployment would need Lakebase credentials provided another way, for example running as a service principal with its own Postgres role (see `logs/evidence_pass_2026-11-01.md` section 12).
* The data is 100% synthetic, with an intentionally seeded fraud cohort. Metrics describe this synthetic set only.
* Dashboard dataset latency (p95 up to 8.7 s) is serverless SQL through UC on compute that was not fully warm. It is not Lakebase point-read latency.