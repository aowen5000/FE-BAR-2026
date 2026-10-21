# FE-BAR-2026

## Layout

* Repo root: pipeline, model, agent and Lakebase source (notebooks, `.py` modules, `.sql` DDL)
* `validation_notebooks/`: check and verify notebooks with committed outputs
  * `gold_feature_validation`: gold feature layer checks
  * `lakebase_sync_validation`: gold to Lakebase synced tables
  * `lakebase_write_path_validation`: `cases` schema write path (`lakebase_cases.py`)
  * `lakebase_scores_validation`: `fraud.txn_risk_current` read path and latency
  * `lakebase_fgac_validation`: Postgres roles, `fraud_gov` views, RLS
  * `fgac_hardening`: Step 5 hardening pass, items 1 to 8
* `logs/`: run logs and evidence

Validation notebooks import repo modules (for example `lakebase_cases`) from the repo root, one level above `validation_notebooks/`.