# Job fe_bar_gold_to_lakebase: run 1101647585612679 (2026-10-21, FGAC hardening Item 3)

Workspace: fevm-workshop-guy. Job ID 1115396029932218. Trigger: ONE_TIME (run_now from the hardening session). Raw JSON: `job_fe_bar_gold_to_lakebase_run_1101647585612679_raw_2026-10-21.json`.

Purpose: prove a SNAPSHOT sync refresh does not break the `fraud_gov` views built on top of the synced tables.

## Task results

| Task | Task run ID | Result | Duration |
| --- | --- | --- | --- |
| gold_pipeline_refresh | 490435646942231 | SUCCESS | 62 s |
| batch_scoring | 348378236508614 | SUCCESS | 174 s (+4 s setup) |
| lakebase_sync_refresh | 742998301546873 | SUCCESS | 52 s |
| Whole run | 1101647585612679 | SUCCESS | 295 s |

## Synced table OIDs (parent partitioned tables, relkind = p)

| Table | OID before | OID after |
| --- | --- | --- |
| fraud.txn_features | 24712 | 24712 |
| fraud.txn_risk_current | 73749 | 73749 |
| fraud.customer_risk_profile | 24743 | 24743 |

The sync did not recreate the parent tables. After the run, `fraud.txn_risk_current` has child partition OID 122901, far above the parent OID, which is consistent with the sync swapping in a new child partition under a stable parent. I did not record child OIDs before the run, so I cannot prove which children were replaced. The views reference the parent tables, so they are unaffected either way.

## fraud_gov views

All three views (`txn_features`, `txn_risk_current`, `customer_risk_profile`) still exist after the run, with the same owner (alex.owen@databricks.com) and the same definition md5.

| Count | Before | After |
| --- | --- | --- |
| fraud_analyst: fraud_gov.txn_features | 463,881 | 463,881 |
| fraud_analyst: fraud_gov.txn_risk_current | 463,881 | 463,881 |
| fraud_analyst: fraud_gov.customer_risk_profile | 9,289 | 9,289 |
| fraud_lead: fraud_gov.txn_features | 464,632 | 464,632 |
| fraud_lead: fraud_gov.txn_risk_current | 464,632 | 464,632 |
| fraud_lead: fraud_gov.customer_risk_profile | 9,289 | 9,289 |

## UC vs Postgres row counts after the run

| UC source | UC rows | Postgres synced table | PG rows | Match |
| --- | --- | --- | --- | --- |
| txn_features_gold | 464,632 | fraud.txn_features | 464,632 | yes |
| customer_risk_profile_gold | 9,289 | fraud.customer_risk_profile | 9,289 | yes |
| scored_transactions | 464,632 | fraud.txn_risk_current | 464,632 | yes |

Freshness: `max(scored_at)` is 2026-10-21T02:36:46.583767Z in both UC and Postgres, so the new scores landed. TXN-0234209 still has risk_score 0.98441 and action block.

## Conclusion

The refresh succeeded and the views survived it, so no fix was needed. Caveat: this test covers an incremental snapshot refresh (`full_refresh=false`). A full refresh or a recreate of a synced table could drop the parent. If that ever breaks the views, the proposed remedy is a post-sync job task that re-runs the idempotent `fraud_gov` section of `lakebase_fgac.sql`. I have not built that task.
