# How to run

Moved from README.md in Step 10, with the Genie Agent, App and business value steps added. Workspace `fevm-workshop-guy`. 100% synthetic data.

## Prerequisites

* Membership in the UC account group `pii`. Training, scoring and `validation_notebooks/business_value.ipynb` stop if `is_account_group_member('pii')` is false, because the row filter and mask would silently remove the high-amount signal.
* A Postgres role with superuser-level rights in `fe_bar_db` (databricks_superuser with BYPASSRLS) for the DDL and FGAC setup.
* Serverless notebook compute and the serverless SQL warehouse `9bbc027402111984`.

## Order

| # | What | File | Re-run behavior |
| --- | --- | --- | --- |
| 1 | Generate synthetic JSON | `card_transaction_bronze_generator.ipynb` | Overwrites the JSON files in the staging volume (`mode("overwrite")`) |
| 2 | SDP pipeline c0db28b8 | `FE BAR Bronze Silver AutoLoader Pipeline.sql`, `gold_feature_layer.sql` | A refresh recomputes the MVs. A full refresh also reprocesses bronze |
| 3 | Train the model | `fraud_model_training.ipynb` | Safe. `REGISTER_MODEL = False` logs a new MLflow run only and does not move @champion |
| 4 | Batch scoring | `fraud_batch_scoring.ipynb` | **Overwrites** `scored_transactions` |
| 5 | Refresh and sync | Job `fe_bar_gold_to_lakebase`, or the sync pipeline f8690359 alone | Refreshes gold, **overwrites** scores, and re-snapshots the synced tables |
| 6 | Lakebase DDL and FGAC | `lakebase_cases_ddl.sql`, `lakebase_fgac.sql`, `lakebase_fgac_hardening.sql`, `lakebase_dashboard.sql` | Written to be idempotent |
| 7 | UC tools (deprecated) | `agent_tools.sql` | `CREATE OR REPLACE`. The agent no longer uses them |
| 8 | Agent demo | `fraud_triage_agent.ipynb` (`fraud_triage_agent.py`, `lakebase_cases.py`) | Reuses the open case for TXN-0234209 (idempotent). `REGISTER_AGENT = False` (D.3 output shows the one-time v3 registration). D.4 loads @champion and explains TXN-0234209 and TXN-0112255 without opening cases |
| 9 | Dashboard | Import `dashboards/fe_bar_fraud_ops.lvdash.json`, set warehouse 9bbc027402111984, publish with embedded credentials | |
| 10 | Genie Agent | `validation_notebooks/genie_agent_validation.ipynb` (pre-flight, creation, export, benchmark); definition `genie/fraud_risk_ops_genie.json` | Attach only the six `fraud_dash` views and `fe_bar_a0.risk_score_calibration`. Grant CAN_RUN per user or group in the space Share dialog |
| 11 | Databricks App | `app/` (`app.py`, `app.yaml`, `requirements.txt`); `scripts/sync_app_modules.py`; `uc_app_grants.sql`; `lakebase_fgac_hardening.sql` Item 9 | Run `scripts/sync_app_modules.py` first so `app/` holds byte-identical copies of the two shared modules. App resources are referenced with `valueFrom` in `app.yaml`. Apply the UC grants and the Postgres role grant for the app service principal, then deploy. Validate with `validation_notebooks/app_validation.ipynb` |
| 12 | Business value | `validation_notebooks/business_value.ipynb` | Read-only. Thresholds come from MLflow run `d89beaca8f81447780da60ed2ea7c811`. Code cell 8 prints the text of `logs/business_value_2026-11-06.md` |

Validation notebooks in `validation_notebooks/` are read-only, with these exceptions. `lakebase_write_path_validation`, `lakebase_fgac_validation` and `fgac_hardening` create test cases and close them. `dashboard_validation` D.2 opens one new live-proof case per run and leaves it open by design. `app_validation` reads a case that a person opened through the App UI.

## Committing notebooks with outputs

Interactive outputs live in the workspace notebook object, not in the `.ipynb` file Git sees. Export each notebook as JUPYTER with the Python SDK and import it back over the same path with `overwrite=True`. Object IDs stay the same. Then commit with the git CLI. Detail: `logs/notebook_outputs_rerun_2026-10-23.md` "Why the first push had no outputs".
