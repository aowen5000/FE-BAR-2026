# End-to-end trace: TXN-0234209

Moved from README.md in Step 10, with hops 10 and 11 added. 100% synthetic data.

TXN-0234209 is the seeded-cohort transaction traced through every step: CUST-08669, $323.96, amt_to_monthly_spend 0.7825, cross-border, new device, is_fraud = true. The selection rule is in `logs/batch_scoring_2026-10-20.md`. "Code cell N" counts code cells only, top to bottom.

| # | Hop | Evidence (committed file and cell/section) | What it shows |
| --- | --- | --- | --- |
| 1 | raw volume / bronze | `validation_notebooks/dashboard_validation.ipynb` code cell 14 "D.3 End-to-end trace", journey table row "raw/bronze"; `logs/lineage_2026-11-01.md` section 2(a) | 2 bronze rows for TXN-0234209: the original plus an injected duplicate. Bronze reads `/Volumes/.../staging/transactions/` |
| 2 | silver | Same cell, row "silver"; `logs/lineage_2026-11-01.md` section 1, hop 2 | 1 row after dedup; edge fact_transactions_bronze -> fact_transactions_silver (pipeline) |
| 3 | gold features | Same cell, row "gold features"; `fraud_batch_scoring.ipynb` code cell 8 "Trace one high-risk seeded-cohort transaction" | 1 row in txn_features_gold; amt_to_monthly_spend 0.7824742766049949, is_cross_border 1, is_new_device 1 |
| 4 | score and SHAP signals | `fraud_batch_scoring.ipynb` code cell 8; `logs/batch_scoring_2026-10-20.md` "Traced seeded-cohort transaction" | risk_score 0.9844108757126732, block; is_new_device +2.5724, geo_distance_from_home 450.63 +1.8741, is_online +1.2001 |
| 5 | scored_transactions | `fraud_batch_scoring.ipynb` code cell 8 (reads the written table); `logs/notebook_outputs_rerun_2026-10-23.md` "Data refreshes" | model_version 1, scored_at 2026-10-24 00:22:56 (scores unchanged by re-runs) |
| 6 | Lakebase fraud.txn_risk_current | `validation_notebooks/lakebase_scores_validation.ipynb` code cell 4 "Traced transaction: UC vs Postgres"; `logs/lakebase_scores_sync_2026-10-20.md` "Traced transaction TXN-0234209"; `dashboard_validation.ipynb` code cell 14 (fraud_gov.txn_risk_current row) | UC = Postgres for risk_score, recommended_action, model_version (all True) |
| 7 | agent explanation and trace | `fraud_triage_agent.ipynb` code cell 3 "E.1: Explain - TXN-0234209 (+ trace span table)", re-run 2026-11-01; `logs/agent_triage_2026-10-21.md`; `logs/agent_trace_2026-10-21.json` | Trace tr-372bc4fc3a27c07127bdc96756ac3920: get_transaction_risk, explain_top_signals, get_customer_history, all `agent_python:postgres:fraud_triage_agent`, no tool errors; confidence medium (block_band precision 0.50, n=288) |
| 8 | case in cases.fraud_cases and its round-trip read | `fraud_triage_agent.ipynb` code cells 4-5 (E.2, E.3); `dashboard_validation.ipynb` code cell 4 "A.3 Cases in Postgres as fraud_lead"; `logs/agent_case_roundtrip_2026-10-21.md` | Case 2319d4b7-bea3-412b-ba6b-8325e1a7a71d, open, auto_block, created_by fraud_triage_copilot:agent, db_inserted_by alex.owen@databricks.com; read back as fraud_lead; 1 open case after 2 "open a case" requests |
| 9 | dashboard dataset | `dashboard_validation.ipynb` code cell 10 "B.3" (PASS) and code cell 14 (ds_triage with the txn_id filter) | ds_triage row: case 2319d4b7, open, auto_block, risk_rank 762; fraud_dash.case_summary shows the same case |
| 10 | Genie Agent (natural language) | `logs/genie_agent_2026-11-03.md` "Benchmarks (Conversation API, final round = round 1)" row 3; `genie_agent_benchmark_evidence_logs/non_pii_test_user_2026-11-05.md` row 3 (message 01f1d8ac56431edcbbbf6673bcd1758b) | "Why was TXN-0234209 flagged?" answered from `fraud_dash.triage_queue`: 0.98441, block, is_new_device +2.5724, geo_distance_from_home +1.8741, is_online +1.2001 (open, auto_block). PASS as pii and as non_pii |
| 11 | re-score by the job (Step 10) | `logs/job_fe_bar_gold_to_lakebase_run_1059811930012881_2026-11-06.md` "Traced transaction TXN-0234209" | risk_score 0.9844108757126732 before and after run 1059811930012881, in UC and Postgres; only scored_at moved |

Gaps, stated honestly:

* Hops 1 and 2 show the bronze and silver row **counts** for TXN-0234209 (2 and 1), not the row contents.
* The raw JSON record in the volume is not printed anywhere in the repo. The volume -> bronze edge is supported by the pipeline source path (`logs/lineage_2026-11-01.md` section 2(a)), not by `system.access.table_lineage`.
* **Databricks App hop: no evidence for TXN-0234209.** The App live test used TXN-0045116 (case 5af3575c-cda8-47cb-97be-021b26dca000, `logs/app_2026-11-04.md`). No committed file shows TXN-0234209 opened in the App.

## Live-read proof, case 030dc7fb

Source: `logs/dashboard_2026-10-22.md` "Live-Read Proof (D.2)". On 2026-10-23 the agent was invoked once for TXN-0350980 and opened case 030dc7fb-3284-4cc2-9264-06b7de57c2cb (trace tr-a378f1a1b9d34fc7e7e7bf911599b31b; the interactive output was lost, so the trace is exported from MLflow to `logs/trace_evidence_2026-11-01.json`). ds_kpi_cases read cases_created_today 0 / open_cases 6 / visible_cases 164 before (01:45:19 UTC) and 1 / 7 / 165 after (01:45:41 UTC). No sync or job ran in between. The case row is also in `logs/dashboard_dataset_results_2026-10-22.md` (ds_triage and ds_recent_cases, created 2026-10-23T01:45:33.754Z).

The notebook cell output of that interactive run was not preserved (see "Evidence status" in the same log). The same proof was repeated twice with outputs kept:

* Job run 659281894932228: case c2b2ec3a, 1 / 7 / 165 to 2 / 8 / 166 (`logs/dashboard_validation_run_659281894932228.md`).
* The committed `dashboard_validation.ipynb` code cell 13 "D.2": case 2c96d428, visible/open 220 / 8 to 221 / 9 (`logs/notebook_outputs_rerun_2026-10-23.md`).

## Case IDs

TXN-0234209 maps to `2319d4b7-bea3-412b-ba6b-8325e1a7a71d` (open, auto_block). Live-read proofs: `030dc7fb-3284-4cc2-9264-06b7de57c2cb` (TXN-0350980), `c2b2ec3a-a1a7-444f-a1c8-969af362c0ee` (TXN-0197951, job run 659281894932228) and `2c96d428-da99-49e5-b6ac-70ebb16e2ce5` (TXN-0112255, committed notebook run). App live test: `5af3575c-cda8-47cb-97be-021b26dca000` (TXN-0045116).
