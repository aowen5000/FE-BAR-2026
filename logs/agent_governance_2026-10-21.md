# Agent Governance Log — 2026-10-21

## UC vs Postgres FGAC Enforcement

### A.5 Before picture: UC FGAC is not propagated to synced tables (documented behavior)
- UC fe_bar_lakebase.fraud.txn_features: 464,632 rows visible, 751 high-amount rows visible, 431,471 non-null amt_to_monthly_spend
- Direct Postgres fraud.txn_features: Same (no RLS before FGAC setup)
- A synced table is a managed copy in Postgres, owned by `databricks_writer_<dbid>`, with access managed by Postgres grants ([Serve lakehouse data with synced tables](https://docs.databricks.com/aws/en/oltp/projects/sync-tables/)). So the UC row filter and column mask on the silver sources do not apply to `fraud.*`. `fraud_gov` changes this by re-applying the same row and column rules in Postgres with security_barrier views keyed on `fraud_pii` membership.

### B.6 After Picture — fraud_gov views through UC
- fe_bar_lakebase.fraud_gov.txn_features via UC: 463,881 rows (751 hidden), 0 high-amount, 0 non-null amt_to_monthly_spend
- Finding: fraud_gov views ARE visible through UC. However, pg_has_role() always returns FALSE through UC. UC reads Lakebase as the per-database system role `databricks_reader_<dbid>` ([Create Postgres roles](https://docs.databricks.com/aws/en/oltp/projects/postgres-roles/)), not as the user's Postgres role. So the views always take the non-pii path through UC, whatever the user's UC group membership. Re-confirmed 2026-10-21: as alex.owen (UC pii member = true) the UC path returns 463,881 rows, 0 high-amount, 0 non-null amt_to_monthly_spend.

## Why create_fraud_case is an Agent-Side Python Tool
UC functions cannot obtain Lakebase OAuth credentials or open Postgres connections. When a UC Python function runs on a Databricks serverless warehouse, it executes in a restricted environment without access to `WorkspaceClient.postgres.generate_database_credential()`. Attempting to import `psycopg` or call Lakebase from a UC function fails with import errors or missing credentials.

Therefore (original Step 5 design, superseded by Item 5 below):
- get_transaction_risk, explain_top_signals, get_customer_history: UC SQL functions reading fe_bar_lakebase.fraud.* through the Lakebase UC catalog
- create_fraud_case: Agent-side Python tool wrapping LakebaseCases(pg_role='fraud_triage_agent'), which uses generate_database_credential() + psycopg directly

Current design (2026-10-21): all four tools are agent-side and Postgres-governed. See Item 5.

## Synced-Table RLS Limitation
The synced tables (fraud.txn_features, fraud.txn_risk_current, fraud.customer_risk_profile) are owned by the sync pipeline's internal writer roles (databricks_writer_*). Postgres ENABLE/FORCE ROW LEVEL SECURITY requires the table owner or a superuser. These tables are managed by the sync pipeline and modifying their RLS would break the sync. Therefore, FGAC on synced tables uses security_barrier views in fraud_gov instead of RLS on the base tables.

## Case Tables Through UC
FORCE ROW LEVEL SECURITY on cases.fraud_cases and cases.case_actions means UC queries (which run as Postgres system roles without any RLS policy) return 0 rows. This is intentional: the case tables are access-controlled exclusively through direct Postgres connections with SET ROLE. The get_customer_history UC function joined to cases.fraud_cases, so its existing_cases section was silently always empty. Re-confirmed 2026-10-21: `SELECT count(*) FROM fe_bar_lakebase.cases.fraud_cases` = 0 through UC while Postgres holds 114 cases. Fixed by Item 5: the agent-side tool returns case 2319d4b7 for CUST-08669.

## Prior Fraud Cases Table
Used: workshop_guy_catalog.fe_bar_a0.fact_prior_fraud_cases_silver
Columns: case_id, customer_id, txn_id, fraud_type, investigation_outcome, recovery_amount, resolution_date
Since 2026-10-21 the agent reads prior outcomes from fraud_gov.customer_risk_profile (prior_case_count, confirmed_fraud_count), which the gold layer derives from this table. CUST-08669: confirmed_fraud=3, total=3 in both.

---

# FGAC hardening additions (2026-10-21)

## Item 4: Alternative considered: filtered-view sync

Documented pattern. Synced tables accept UC views (and materialized views) as sources. Snapshot mode copies the whole source on each sync and only needs `SELECT *` on it ([Serve lakehouse data with synced tables: supported sources and sync modes](https://docs.databricks.com/aws/en/oltp/projects/sync-tables/)). So you can sync a pre-filtered UC view in Snapshot mode, for example `SELECT ... FROM txn_features_gold WHERE amount <= 10000` with `amt_to_monthly_spend` dropped. Restricted rows and columns then never land in Postgres at all. Caveat: I did not find a docs page that names this as an FGAC recipe. It is the combination of "views are supported sources" and "Snapshot copies SELECT *".

Why a dynamic filter would not work there. A view filter such as `WHERE amount <= 10000 OR is_account_group_member('pii')` is evaluated once, when the sync pipeline reads the view, not when a Postgres user queries the copy. Pipelines evaluate identity functions as the pipeline owner during refresh ([Use Unity Catalog with pipelines: row filter and column mask behavior](https://docs.databricks.com/aws/en/ldp/unity-catalog/), "Refresh as owner"). The sync pipeline f8690359 has creator and run_as `alex.owen@databricks.com`, who is in `pii`, so the filter would pass every row and the copy would be unfiltered. Synced copies are static per sync, so a dynamic per-user filter cannot work.

Tradeoff.

| | Filtered-view sync (static) | One copy + dynamic Postgres views (this build) |
| --- | --- | --- |
| Where restricted data lives | Never in the non-pii copy | In Postgres, hidden by fraud_gov views |
| Copies | One synced table per persona (e.g. txn_features_nonpii and txn_features_pii) | One synced table per source |
| Storage / sync cost | ~2x storage and sync runs for persona-split tables | 1x |
| Rule changes | Change the UC view and re-sync | `CREATE OR REPLACE VIEW` in Postgres, instant |
| Identity source | UC grants on each synced table plus Postgres grants per copy | Postgres role membership (fraud_pii), mirrored from UC by pii_role_sync.py |
| Blast radius of a Postgres grant mistake | Low (data is absent) | Higher (data present, a mis-grant on fraud.* exposes it) |

Why this build uses fraud_gov views. There are two personas and the rules are simple predicates on one source each. One synced copy keeps the sync job and storage unchanged. The rules can be tested per role with SET ROLE (8/8 deny tests). The agent and analysts share one set of tables, and the case-table RLS can reuse the same views. The main risk, a direct grant on `fraud.*`, is mitigated: no governed role has any grant on `fraud.*`, and direct SELECT is denied for all three roles. For a stricter regime where restricted rows must not exist in the serving database at all, use the filtered-view sync for the non-pii copy.

## Item 5: Read tools must run under some governance

Check (2026-10-21). Objects read by each UC function in agent_tools.sql:

| UC function | Objects read | Governance that applies |
| --- | --- | --- |
| get_transaction_risk | fe_bar_lakebase.fraud.txn_risk_current, fe_bar_lakebase.fraud.txn_features | None (synced tables, no UC filter or mask, no Postgres RLS) |
| explain_top_signals | fe_bar_lakebase.fraud.txn_risk_current, fe_bar_lakebase.fraud.txn_features, fe_bar_lakebase.fraud.customer_risk_profile | None |
| get_customer_history | fe_bar_lakebase.fraud.customer_risk_profile, fe_bar_lakebase.fraud.txn_risk_current, fe_bar_lakebase.fraud.txn_features, workshop_guy_catalog.fe_bar_a0.fact_prior_fraud_cases_silver, fe_bar_lakebase.cases.fraud_cases | Only the silver table (UC). cases.fraud_cases returns 0 rows through UC |

The fraud_gov views are visible through UC as fe_bar_lakebase.fraud_gov.*, but they filter every caller (pii member alex.owen included) because UC reads as `databricks_reader_<dbid>`. So the rules are not identity-aware on the UC path. I could not test a non-pii identity on the UC path: the only human principal available is alex.owen, who is in pii. The rules therefore cannot be shown to apply per identity there.

Fix (rule: governed by UC or by Postgres, never neither). The three read tools are now agent-side Python tools in fraud_triage_agent.py, with the same names, signatures and docstrings. They query fraud_gov.* (plus RLS-protected cases.fraud_cases) through `LakebaseCases(pg_role='fraud_triage_agent')`. The UC functions stay in agent_tools.sql with DEPRECATED COMMENTs and are not registered with the agent. Each tool returns `_implementation` and `_objects_read` so traces show what ran and what it read. Trace evidence is in fraud_triage_agent.ipynb and logs/fgac_hardening_2026-10-21.md.

## Item 6: Before-check wording

The Part A.5 section is retitled "Before picture: UC FGAC is not propagated to synced tables (documented behavior)" in lakebase_fgac_validation.ipynb, logs/lakebase_fgac_2026-10-21.md and this log. The numbers are unchanged, and the docs link and a sentence on what fraud_gov changes are added.

## Item 7: Tamper-resistant attribution

Before: as fraud_triage_agent, an INSERT with created_by `fraud_triage_copilot:someone_else@example.com` succeeded (case 71cb5cac, rolled back). The only check was the `fraud_triage_copilot%` prefix.

Now: `cases.fraud_cases` and `cases.case_actions` have `db_inserted_by TEXT NOT NULL DEFAULT session_user`. The agent INSERT policies also require `db_inserted_by = session_user`, so an insert claiming another login fails with "new row violates row-level security policy". Existing rows (114 cases, 226 actions) were backfilled with `alex.owen@databricks.com`. Reason: it is the only human LOGIN role in fe_bar_db, every case write went through that login (with or without SET ROLE, session_user stays the login), and the other login roles are Databricks system or sync roles that never write cases.*.

The honest claim: **the database records which identity connected, the analyst label is supplied by the agent.** `created_by` / `actor` are still free-text labels set by the agent and can only be trusted as far as the agent is trusted. `db_inserted_by` is set and checked by Postgres. Today both the agent and the notebooks connect as alex.owen, so db_inserted_by does not yet tell the agent apart from a human. In production, the agent should connect as its own service principal so db_inserted_by identifies it. Admin logins with BYPASSRLS can still write any value. That is expected for break-glass access.

## Item 8: Calibrated confidence and PII mapping

Confidence is no longer the "threshold +/- 0.03" placeholder. It comes from `fraud_gov.risk_score_calibration`, synced from `workshop_guy_catalog.fe_bar_a0.risk_score_calibration`. That table holds the observed fraud rate per risk_score bucket on the champion test set: time split 80/20 at 2026-09-21 15:20:18, 92,927 rows, run d89beaca8f81447780da60ed2ea7c811. The buckets are deciles below the review threshold, plus review_band and block_band. Confidence is high if observed precision >= 0.70, medium if >= 0.30, else low. Cut-offs and the table are logged as params on MLflow run b78f0a3ba3f04ab6b970d1da4744bb9e (experiment /Users/alex.owen@databricks.com/fe_bar_fraud_triage_agent). Result: block_band precision 0.50 (144/288) gives medium, review_band 0.25 gives low, and every decile is <= 0.044, so low. TXN-0234209 is now "medium (observed precision 0.50 in block_band, n=288)" instead of "high". Semantic note: for approve-band transactions, "low" here means low fraud precision, not low certainty that the transaction is legitimate. The rule follows the requested definition.

PII mapping. `pii_role_sync.py` reads the members of the UC group `pii` (nested groups expanded). For each member it computes whether a Postgres login role exists in fe_bar_db and whether that role is in fraud_pii, and it plans `none`, `grant_fraud_pii` or `create_role_and_grant`. Direct fraud_pii members not in `pii` are reported as revoke candidates; the structural members fraud_lead and fraud_triage_agent are excluded. Dry run (2026-10-21): one member, alex.owen@databricks.com, role exists, already in fraud_pii, action `none`. Applying for my identity would be a no-op, and I did not run apply. The production path to replace the manual GRANTs in lakebase_fgac.sql is a scheduled Lakeflow job running `pii_role_sync.py --apply`, for example hourly, under a service principal that is databricks_superuser on fe_bar_db. That path is not built yet. Revocation should be enabled only after review, because removing someone from `pii` in UC would then remove their Postgres access automatically.
