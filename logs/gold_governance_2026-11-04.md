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

## Catalog grant narrowing (user-approved; applied by the user from `validation_notebooks/catalog_grant_narrowing.ipynb` cell 2, verified by cell 3)

`workshop_guy_catalog` is shared. It has 17 other schemas, mostly bo.cheng's, and three non-owner service principals read or wrote them in the last 90 days, all through the `account users` catalog grant. Unity Catalog grants inherit and a schema cannot block them, so the catalog grant was replaced:

| Level | account users before | account users after |
| --- | --- | --- |
| Catalog | ALL PRIVILEGES, MANAGE, EXTERNAL USE SCHEMA | USE CATALOG, CREATE SCHEMA, BROWSE |
| 17 other schemas | Inherited from the catalog | ALL PRIVILEGES, MANAGE, EXTERNAL USE SCHEMA granted on each schema (same effective access) |
| `fe_bar_a0` | Inherited full access (48 object-privilege rows) | USE SCHEMA, plus SELECT on `fact_transactions_silver`, `dim_customer_silver`, `dim_merchant_silver`, `customer_risk_profile_gold`, `risk_score_calibration` |

* **66 statements.** `REVOKE ALL PRIVILEGES` on the catalog also removed the USE CATALOG / CREATE SCHEMA / BROWSE grants made just before it. The cell detected this and re-granted them a few seconds later, so `account users` briefly had no USE CATALOG.
* **Checks: 29/29 PASS.**
  * Catalog privileges are exactly as planned, and alex.owen keeps ALL PRIVILEGES and MANAGE.
  * All 17 other schemas keep their three privileges.
  * `fe_bar_a0` has USE SCHEMA only, with SELECT on the 5 objects.
  * No `account users` privilege on `scored_transactions`, `txn_features_gold`, the 4 bronze tables or the `staging` volume.
  * The owner identity still reads `scored_transactions` (464,632 rows).
* **Rollback:** grant ALL PRIVILEGES, MANAGE and EXTERNAL USE SCHEMA on the catalog back to `account users`.
* **Not yet tested as a non-owner identity:** the non_pii test user (`non_pii`, user ID 72697000497660) should get a permission error on `scored_transactions` and the bronze tables, while the Genie space still works.
* **Behavior change for other teams:** schemas created after this are no longer readable by everyone automatically.

## Revoke on customer_risk_profile_gold (user-run, verified read-only)

* **Why:** `customer_risk_profile_gold` is built by the pipeline as the owner (a `pii` member), so its 30-day counts (`txn_count_30d`, `cross_border_txns_30d`, `distinct_devices_30d`, `distinct_countries_30d`) and `last_txn_ts` include transactions over $10,000. A reader outside `pii` could compare them with their own filtered counts from `fact_transactions_silver` and infer that hidden high-value transactions exist. This showed up for 151 of 9,289 customers (162 inferable transactions; the inferred amounts stay hidden because `avg_amount_30d` is masked). Simulated from the filter rule, not tested as a non-pii identity.
* **Fix (least disruptive):** the user ran `REVOKE SELECT ... customer_risk_profile_gold FROM account users`. In the last 90 days only the owner and system processes read the table; the pipeline, scoring, Lakebase sync and agent run as the owner, and the Genie space and dashboard do not use it.
* **Verified** with information_schema.table_privileges and `SHOW GRANTS`: no `account users` SELECT on the table; only READ METADATA at metastore level remains. `account users` now has SELECT on 4 `fe_bar_a0` objects: `fact_transactions_silver`, `dim_customer_silver`, `dim_merchant_silver`, `risk_score_calibration`.
* **Not checked:** whether the Postgres `fraud_gov` views allow the same comparison over a direct `fraud_analyst` connection.

## Still open

* **High-value cases cannot be triaged:** the `fraud_dash` views drop amounts over $10,000 for everyone, so 705 flagged transactions (200 fraud, $3,588,732.92) are invisible in Genie and the dashboard. Options under discussion: redact the amount instead of filtering rows, or a separate pii-only view schema.
* **`scored_transactions`:** closed to `account users` by the catalog grant narrowing above. There is still no row filter or mask on the table itself, which only matters for principals granted access directly.
* **`txn_features_gold.amt_to_monthly_spend`:** unmasked, but the table is now closed to `account users`.
* **Other schemas:** `account users` keeps MANAGE on the 17 other schemas (their owners' decision).
* **Genie space access:** the non_pii test user (user ID 72697000497660, the only `non_pii` member) has CAN_RUN on the space directly as a user; the `non_pii` group itself has none. Their benchmark re-run (item 5) is pending, and as space owner I can grade their conversations through the Genie API.
