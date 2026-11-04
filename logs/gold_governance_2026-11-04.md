# Step 8 follow-up: gold governance hardening and non_pii access (2026-11-04)

Workspace fevm-workshop-guy. Genie Code conversation 2326365276521178. Branch `step8b/2026-11-04_fevm-workshop-guy_conv-2326365276521178`. Evidence notebook: `validation_notebooks/gold_governance_hardening.ipynb` (committed with outputs). Every change below was approved by the user in this conversation.

## Why

Step 8 found that `scored_transactions` and `txn_features_gold` had no row filter, and that `customer_risk_profile_gold.avg_amount_30d` averages unfiltered transactions, while `account users` holds ALL PRIVILEGES (and MANAGE) on `workshop_guy_catalog`.

## Changes

| Object | Change | How | State now |
| --- | --- | --- | --- |
| `txn_features_gold` | Row filter `filter_high_amount_txns` ON (`amount`) | `WITH ROW FILTER` in `gold_feature_layer.sql`, applied by the pipeline update in job run 273696236528085 | In place |
| `customer_risk_profile_gold` | New mask `mask_avg_amount_30d` on `avg_amount_30d` (`IF(IS_ACCOUNT_GROUP_MEMBER('pii'), avg_amount_30d, NULL)`) | New UC function plus a column list with `MASK` in `gold_feature_layer.sql` | In place |
| `scored_transactions` | Row filter `filter_high_amount_txns` ON (`amount`) | `ALTER TABLE ... SET ROW FILTER` | Removed again (option B, below) |
| `fe_bar_lakebase` | `non_pii` (account group, 1 member, no overlap with `pii`): USE CATALOG, USE SCHEMA on `fraud_dash`, SELECT on the six `fraud_dash` views | SQL run by the user | In place. No grants on `fraud`, `fraud_gov` or `cases` |
| Genie space `01f1d7b464d510b9aa6cde48300787ca` | CAN_RUN for `non_pii` | Not done | Pending: the user adds it with Share > Can Run |

## Job / sync test

* Job `fe_bar_gold_to_lakebase`, run 273696236528085 (2026-11-04 00:41 to 00:46 UTC):
  * `gold_pipeline_refresh` SUCCESS. The filter and mask were applied.
  * `batch_scoring` SUCCESS. `INSERT OVERWRITE` into the filtered `scored_transactions` works.
  * `lakebase_sync_refresh` FAILED: `SYNCED_TABLE_USER_ERROR.SOURCE_READ_ERROR` / `ROW_LEVEL_SECURITY_FEATURE_NOT_SUPPORTED.TIME_TRAVEL` on `scored_transactions`. Synced tables read a pinned table version, and time travel is not supported on a table with a table-level row filter.
  * The synced tables stayed online with the previous snapshot.
* Option B (user decision): dropped the `scored_transactions` row filter, then re-ran the sync pipeline (update d1502c56). It COMPLETED in 60 s, and all four synced tables are `SYNCED_TABLE_ONLINE_NO_PENDING_UPDATE`.
  * This shows the materialized views with a row filter (`txn_features_gold`) and a column mask (`customer_risk_profile_gold`) do sync.
* After-checks: 25/25 PASS (notebook cell 4).
  * Row counts are unchanged for a pii reader across the 3 gold tables, 4 synced tables and 6 fraud_dash views.
  * The pii reader still sees the 751 rows with amount > 10000, and sum(avg_amount_30d) = 2,010,281.99 is unchanged.
  * Lakebase still holds the full values (751 rows; avg_amount_30d unmasked), because the sync identity is a pii member. Governance in Postgres stays with the `fraud_gov` / `fraud_dash` views.
  * Non-pii view, computed from the filter's non-pii branch: 463,881 of 464,632 rows in `txn_features_gold`; avg_amount_30d NULL. This was not tested as a real non-pii identity.
* The full job was not re-run after option B. Only the sync pipeline was.

## Still open

* **`scored_transactions` is unprotected for non-pii users:** 751 rows with amount > 10000, and `amt_to_monthly_spend` values inside `top_shap_signals`. Fix options: an ABAC policy that exempts the sync identity (time travel is supported for exempt principals), or narrower catalog grants.
* **`txn_features_gold.amt_to_monthly_spend` is unmasked** (not approved yet).
* **`account users` has MANAGE on `workshop_guy_catalog`,** which likely lets any user remove the filters and masks.
* **CAN_RUN on the Genie space for `non_pii`** is not granted yet. The benchmark re-run as a non-pii identity (item 5) needs that member (Connor Hauenstein) to run it.
