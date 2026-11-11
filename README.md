# FE-BAR-2026: fraud triage for a regional card issuer

A fraud risk build on Databricks for the fraud operations team of a regional card issuer, in workspace `fevm-workshop-guy`. It uses 100% synthetic data.

## Business outcome

A regional card issuer's fraud ops team has more flagged transactions than it can review. The static rule (cross-border AND new device) flags with no priority and no explanation. Two personas use this build: the Head of Fraud Risk Ops, who watches exposure, model performance and case volume, and the Fraud Analyst, who works the triage queue and opens cases. On the governed view, which excludes transactions over $10,000, the model's block + review bands catch $7,010,482.03 of fraud vs $933,889.13 for the rule. False positives drop from 30,956 to 17,630 (rate 6.83% to 3.89%). On the full synthetic set the model catches $10,599,214.95 vs $1,114,720.20. The agent explains a flagged transaction in 19.9 s median over 9 traced runs. Analyst minutes per case are assumptions from the original plan. The scaled issuer numbers (log section "B.4") are illustrative, not measured. Source: [validation_notebooks/business_value.ipynb](validation_notebooks/business_value.ipynb), [logs/business_value_2026-11-06.md](logs/business_value_2026-11-06.md).

## For reviewers: read in this order

1. [README.md](README.md): problem, KPIs, six stages and how they connect.
2. [EVIDENCE.md](EVIDENCE.md): text proof per stage, each block with its source.
3. [EVIDENCE_APP.md](EVIDENCE_APP.md): proof for App, high-value triage, job run.
4. [DECISIONS.md](DECISIONS.md): design choices and the trade-offs behind them.
5. [docs/TRACE.md](docs/TRACE.md): one transaction followed end to end.
6. [docs/LIMITATIONS.md](docs/LIMITATIONS.md): known gaps and open items.
7. [BUILD.md](BUILD.md): how each step was built, with conversation IDs.
8. [logs/business_value_2026-11-06.md](logs/business_value_2026-11-06.md): KPI math, measured vs assumed.
9. [logs/high_value_triage_2026-11-09.md](logs/high_value_triage_2026-11-09.md): high-value transactions triageable, governance intact.

EVIDENCE.md and EVIDENCE_APP.md quote the committed notebook outputs as text, so the notebooks themselves are optional reading. Evidence index: [EVIDENCE_INDEX.md](EVIDENCE_INDEX.md). Also in docs/: [ARCHITECTURE](docs/ARCHITECTURE.md), [RESOURCES](docs/RESOURCES.md), [HOW_TO_RUN](docs/HOW_TO_RUN.md), [CONVERSATION_IDS](docs/CONVERSATION_IDS.md).

## KPIs

Copied from `logs/business_value_2026-11-06.md` "B.5 Final KPI table".

| KPI | Baseline | With the build | Scope | Source cell or assumption |
|---|---|---|---|---|
| Time to flag and explain a risky transaction | Hours (assumption: manual queue, original plan) | Scored in batch; agent explains in 19.9 s median (16.0 to 51.1 s, 9 runs) | Agent traces | B.3b, measured |
| Analyst time per case | 15 to 20 min (assumption) | 2 to 3 min (assumption) | Per case | Original plan assumption |
| Analyst hours per month | 1,428 to 1,904 (rule queue, manual) | 137 to 205 (model queue, with agent) | Governed view | B.3a, measured volume x assumed minutes |
| False positive rate | 6.83% | 3.89% | Governed view | B.2, measured |
| False positives (count) | 30,956 | 17,630 | Governed view | B.2, measured |
| Fraud $ caught (flagged before approval) | $933,889.13 | $7,010,482.03 | Governed view | B.2, measured |
| Fraud $ caught (flagged before approval) | $1,114,720.20 | $10,599,214.95 | Full synthetic set | B.4b-3, measured |
| Fraud $ missed | $7,052,318.79 | $975,725.89 | Governed view | B.2, measured |
| Fraud $ missed | $10,556,008.99 | $1,071,514.24 | Full synthetic set | B.4b-3, measured |
| High-value flagged txns triageable (200 fraud, $3,588,732.92) | 0 | 705: App in full; Genie and dashboard with amount redacted | amount > 10000 | Step 11, `validation_notebooks/high_value_triage.ipynb` E.1, measured |

Governed view = 463,881 txns; full synthetic set = 464,632 txns (same log, "B.4b-3").

## Six required stages

| # | Stage | What was built | Databricks feature | Headline number | Evidence |
| --- | --- | --- | --- | --- | --- |
| 1 | Lakeflow (ingest) | Bronze, silver and gold tables from JSON in a UC volume | Spark Declarative Pipeline c0db28b8 (Auto Loader + expectations) | 464,679 silver txns; 17,932 txn rows dropped by expectations (update 60f6d1de) | [EVIDENCE.md](EVIDENCE.md#lakeflow-ingest); `logs/update_60f6d1de_full_refresh_2026-10-15.md` |
| 2 | Unity Catalog (govern) | Row filter and masks on silver and gold; `account users` narrowed to least privilege; direct grants for the App service principal | UC row filters, column masks, grants | Gold after-checks 25/25 PASS; grant narrowing 29/29 PASS | [EVIDENCE.md](EVIDENCE.md#unity-catalog-govern); `logs/gold_governance_2026-11-04.md`; `validation_notebooks/gold_governance_hardening.ipynb`; `validation_notebooks/catalog_grant_narrowing.ipynb`; `uc_app_grants.sql` |
| 3 | Lakebase (operational serving) | SNAPSHOT synced tables, OLTP case tables, Postgres FGAC | Lakebase Postgres, synced tables | UC 464,632 = Postgres 464,632; PK lookup p95 3.18 ms | [EVIDENCE.md](EVIDENCE.md#lakebase-operational-serving); `logs/lakebase_scores_sync_2026-10-20.md`; `logs/lakebase_fgac_2026-10-21.md` |
| 4 | ML and Gen AI (make it intelligent) | LightGBM risk model with top-3 SHAP signals; Fraud Triage Copilot agent that explains and opens cases | MLflow, UC model registry, Foundation Model API | ROC-AUC 0.8448, PR-AUC 0.2808; case 2319d4b7 | [EVIDENCE.md](EVIDENCE.md#ml-and-gen-ai-make-it-intelligent); `logs/ml_training_2026-10-20.md`; `logs/agent_triage_2026-10-21.md` |
| 5 | Genie Agent (natural language) | Genie space FE Bar Fraud Risk Ops over six `fraud_dash` views and `risk_score_calibration` | Genie Agent | 13/13 as pii (Step 11); 11/11 as non_pii (Step 8e) | [EVIDENCE.md](EVIDENCE.md#genie-agent-natural-language); `logs/genie_agent_2026-11-03.md`; `genie_agent_benchmark_evidence_logs/non_pii_test_user_2026-11-05.md` |
| 6 | Databricks App (surface it to the business) | Streamlit app `fe-bar-fraud-triage`: triage queue, Explain / Open case, Ask Genie, dashboard link | Databricks Apps, AI/BI dashboard | app_validation 15/15 PASS; live-test case 5af3575c | [EVIDENCE_APP.md](EVIDENCE_APP.md#databricks-app-surface-it-to-the-business); `logs/app_2026-11-04.md`; `validation_notebooks/app_validation.ipynb` |

Job `fe_bar_gold_to_lakebase` run 1059811930012881 (2026-11-06): SUCCESS in 267 s, all three tasks green ([EVIDENCE_APP.md](EVIDENCE_APP.md#job-run-step-10-part-c)).

## How the stages connect

```
 Synthetic JSON in UC volume fe_bar_a0.staging (100% synthetic)
   | Auto Loader
   v
 [1 Lakeflow] Spark Declarative Pipeline c0db28b8
   bronze STs -> silver MVs (expectations, dedup) -> gold MVs
   | [2 Unity Catalog] row filter amount > 10000, masks, least-privilege grants
   v
 [4 ML] fraud_risk_model@champion -> scored_transactions (+ top 3 SHAP)
   | job fe_bar_gold_to_lakebase: gold refresh -> batch scoring -> sync
   v
 [3 Lakebase] Postgres fe_bar_db
   fraud.* (SNAPSHOT synced) -> fraud_gov.* (governed views) -> fraud_dash.* (non-pii views)
   cases.* (OLTP, FORCE RLS) <-- [4 Gen AI] Fraud Triage Copilot (role fraud_triage_agent)
   | UC catalog fe_bar_lakebase
   +---------------------------+------------------------+
   v                           v                        v
 [5 Genie Agent]            AI/BI dashboard        [6 Databricks App] fe-bar-fraud-triage
 FE Bar Fraud Risk Ops      (live read)            triage queue, Explain / Open case
   ^                                               (in-process agent, own Postgres role)
   +------------------ Ask Genie ------------------+
```

Trace of TXN-0234209 (CUST-08669, $323.96, is_fraud = true). Details in [EVIDENCE.md](EVIDENCE.md) and [docs/TRACE.md](docs/TRACE.md).

1. Bronze 2 rows (original plus an injected duplicate), silver 1 row.
2. Gold: amt_to_monthly_spend 0.7825, cross-border, new device.
3. Score 0.9844108757126732, block; top signal is_new_device +2.5724.
4. Lakebase `fraud.txn_risk_current`: UC = Postgres.
5. Agent trace tr-372bc4fc3a27c07127bdc96756ac3920; case 2319d4b7, auto_block, read back as fraud_lead.
6. Dashboard ds_triage row, risk_rank 762.
7. Genie: "Why was TXN-0234209 flagged?" PASS as pii and as non_pii.
8. Job run 1059811930012881: risk_score unchanged.
9. App: gap. The App live test used TXN-0045116 (case 5af3575c).

## Commit identities

All commits in this repo are by me, Alex Owen. Commits authored `aowen5000@gmail.com` were made through the Databricks Git folder integration with my personal GitHub credential `aowen5000`, plus the initial commit and the PR #1 merge in the GitHub web UI. Commits authored `alex.owen@databricks.com` were made with the git CLI in the same Git folder, which uses my workspace identity. That email is verified on my Databricks EMU GitHub account, so GitHub cannot also link it to `aowen5000`, and those commits show as unlinked. History was not rewritten.
