# FGAC hardening log: 2026-10-21

Workspace: fevm-workshop-guy. Genie conversation ID: 1507503687185838. Branch: feature/fgac-hardening.
Lakebase: project fe-bar-fraud-analytics / branch production / database fe_bar_db, UC catalog fe_bar_lakebase.
Notebook evidence: `fgac_hardening.ipynb`. SQL: `lakebase_fgac_hardening.sql` (idempotent, re-run twice with no error).
No UC row filters, column masks, UC group memberships, gold/silver tables or synced tables were changed.
Dates are UTC (2026-10-21).

## Item 1: admin not locked out of case tables
* CHECK: `alex.owen@databricks.com`: rolsuper=false, rolbypassrls=true, member of databricks_superuser. RLS on cases.fraud_cases and cases.case_actions: enabled=true, forced=true. With no SET ROLE: 114 cases, 226 actions visible. Round trip with `LakebaseCases()` (no pg_role) on non-traced TXN-0248594: case 04a5bfa1 created and closed OK.
* FIX: no change needed. BYPASSRLS also bypasses FORCE. An admin policy is documented, commented out, in lakebase_fgac_hardening.sql and lakebase_fgac.sql, for an admin without BYPASSRLS. FORCE was not removed.
* VERIFY: the round trip is repeated in fgac_hardening.ipynb (Item 1 cell). lakebase_write_path_validation.ipynb was re-run end to end, with outputs committed.
* Errors: none. (An earlier ad-hoc attempt on TXN-0000001 failed only because that txn_id does not exist.)

## Item 2: SET ROLE into every test role
* CHECK: pg_has_role(session_user, role, 'MEMBER') = true for fraud_pii, fraud_analyst, fraud_lead, fraud_triage_agent. SET ROLE then RESET ROLE succeeded for all four (current_user switched as expected).
* FIX: no change needed. The grants already come from lakebase_fgac.sql (`GRANT <role> TO CURRENT_USER`). Note: the fraud_pii membership alex.owen holds for testing is in addition to the real UC `pii` membership. pii_role_sync.py (Item 8) is the mapping path.
* VERIFY: all four succeed (fgac_hardening.ipynb Item 2 cell). lakebase_fgac_validation.ipynb was re-run end to end, with outputs committed.

## Item 3: sync refresh must not break fraud_gov views
* CHECK (before the run): view md5 txn_features 9f4c89e3, txn_risk_current e95b38e7, customer_risk_profile 3034e6f2, owner alex.owen. Synced parent OIDs: txn_features 24712, txn_risk_current 73749, customer_risk_profile 24743 (all relkind p, partitioned). Counts: analyst 463,881 / 463,881 / 9,289; lead 464,632 / 464,632 / 9,289.
* TEST: job fe_bar_gold_to_lakebase run 1101647585612679: SUCCESS in 295 s (gold_pipeline_refresh 62 s, batch_scoring 174 s, lakebase_sync_refresh 52 s).
* VERIFY: parent OIDs unchanged, so the tables were not recreated. txn_risk_current now has child partition OID 122901, which is consistent with a child-partition swap; child OIDs were not recorded before the run. Views exist with the same owner and definitions. Analyst and lead counts are unchanged. UC vs Postgres counts match (464,632 / 9,289 / 464,632). max(scored_at) 2026-10-21T02:36:46.58Z on both sides.
* FIX: no change needed. Caveat: only an incremental snapshot refresh was tested. A full refresh or a recreate could drop the parent table. The proposed remedy, not built, is a post-sync job task that re-runs the fraud_gov section of lakebase_fgac.sql.
* Evidence: logs/job_fe_bar_gold_to_lakebase_run_1101647585612679_2026-10-21.md and the matching _raw_ JSON.

## Item 4: alternative FGAC design documented
* CHECK: not applicable (documentation only).
* FIX: added the section "Alternative considered: filtered-view sync" to logs/agent_governance_2026-10-21.md. It covers the pattern, why a dynamic is_account_group_member filter fails (sync pipeline f8690359 runs as alex.owen, who is in pii; identity functions are evaluated as the pipeline owner), the per-persona copy vs dynamic-view tradeoff, and why this build keeps fraud_gov, with docs links. The design is unchanged.
* VERIFY: the section is present. Caveat: I found no docs page that names the filtered-view sync as an FGAC recipe. It is derived from "views are supported sources" plus "Snapshot copies SELECT *".

## Item 5: agent read tools always under governance
* CHECK: all three UC functions read only fe_bar_lakebase.fraud.* synced tables, which have no governance. get_customer_history also reads the UC-governed fact_prior_fraud_cases_silver and fe_bar_lakebase.cases.fraud_cases, which returns **0 rows through UC** because of RLS, so its existing_cases section was always empty. fe_bar_lakebase.fraud_gov.* is visible through UC, but it returns 463,881 rows, 0 high-amount and 0 non-null amt_to_monthly_spend for alex.owen, who IS in pii. Filtering applies to everyone because UC reads as `databricks_reader_<dbid>`, so it is not identity-aware. A non-pii identity on the UC path could NOT be tested: alex.owen is the only human principal available.
* FIX: under the rule, the UC path cannot show per-identity rules, so the three read tools are now agent-side Python tools in fraud_triage_agent.py. They keep the same names, signatures and docstrings and query fraud_gov.* (plus RLS-protected cases.fraud_cases) through `LakebaseCases(pg_role='fraud_triage_agent')`. lakebase_cases.py gained a read-only `query()` helper. The UC functions stay in agent_tools.sql and were redeployed with DEPRECATED COMMENTs. They are not registered with the agent: `UCFunctionToolkit` was removed.
* VERIFY: TXN-0234209 explain run, trace tr-69e222b86590f5a587f13d5dc3a6cb69 (session dry run; the notebook run trace is tr-f7e09df1c76848b6ffa8e5ca07e3fe95, printed in fraud_triage_agent.ipynb). Tool spans:

| tool span | implementation | objects read |
| --- | --- | --- |
| get_transaction_risk | agent_python:postgres:fraud_triage_agent | fraud_gov.txn_risk_current, fraud_gov.txn_features, fraud_gov.risk_score_calibration |
| explain_top_signals | agent_python:postgres:fraud_triage_agent | fraud_gov.txn_risk_current, fraud_gov.txn_features, fraud_gov.customer_risk_profile |
| get_customer_history | agent_python:postgres:fraud_triage_agent | fraud_gov.customer_risk_profile, fraud_gov.txn_risk_current, fraud_gov.txn_features, cases.fraud_cases |

get_customer_history now returns existing case 2319d4b7 for CUST-08669. Prior outcomes (3 confirmed / 3 total) match fact_prior_fraud_cases_silver.

## Item 6: before-check wording
* CHECK: the A.5 section was titled as a plain before/after picture.
* FIX: retitled "Before picture: UC FGAC is not propagated to synced tables (documented behavior)" in lakebase_fgac_validation.ipynb (new A.5 header and numbers cell), logs/lakebase_fgac_2026-10-21.md and logs/agent_governance_2026-10-21.md. Numbers kept (464,632 / 751 / 431,471). Added the docs link (sync-tables) and one sentence on what fraud_gov changes.
* VERIFY: the A.5 numbers cell is re-run in the validation notebook.

## Item 7: tamper-resistant attribution
* CHECK (pre-fix): as fraud_triage_agent, an INSERT with created_by `fraud_triage_copilot:someone_else@example.com` SUCCEEDED (case 71cb5cac-0b11-4b16-8e13-3fd6a73ac200; the transaction was rolled back, so nothing persisted).
* FIX: `db_inserted_by TEXT NOT NULL DEFAULT session_user` added on cases.fraud_cases and cases.case_actions. Both agent INSERT policies now also require `db_inserted_by = session_user`. Backfill: 114 cases and 226 actions set to `alex.owen@databricks.com`, the only human LOGIN role in fe_bar_db. Every case write went through that login, and SET ROLE does not change session_user. The other login roles (cloud_admin, databricks_control_plane, databricks_gateway, databricks_monitor, databricks_reader_*, databricks_writer_*) are system or sync roles. The column was added nullable, backfilled, then set to DEFAULT and NOT NULL, so existing rows were not stamped by the DDL session. created_by stays the agent-supplied analyst label. get_case returns db_inserted_by for cases and actions.
* VERIFY: an agent INSERT with db_inserted_by='someone_else@example.com' was REJECTED: `InsufficientPrivilege: new row violates row-level security policy for table "fraud_cases"`. A normal agent insert records db_inserted_by = the connecting login (fgac_hardening.ipynb Item 7 cell).
* Honest claim: **the database records which identity connected, the analyst label is supplied by the agent.** Today the agent and humans both connect as alex.owen, so db_inserted_by cannot tell them apart until the agent uses its own service principal.

## Item 8: calibrated confidence and PII mapping
* CHECK: the confidence rule was the placeholder "0.03 beyond the threshold". Under it, TXN-0234209 was "high".
* FIX: built workshop_guy_catalog.fe_bar_a0.risk_score_calibration from the champion test set: time split 80/20 at 2026-09-21 15:20:18, 92,927 rows, matching run param test_rows, run d89beaca8f81447780da60ed2ea7c811. Buckets: deciles of risk_score below review_threshold, plus review_band [0.871416, 0.950267) and block_band [0.950267, 1.0]. Synced as fe_bar_lakebase.fraud.risk_score_calibration (SNAPSHOT, existing pipeline f8690359 reused, update af5f4a17 COMPLETED, ONLINE, 12 rows). Added the fraud_gov.risk_score_calibration view and grants. Confidence = high if observed precision >= 0.70, medium if >= 0.30, else low. The live get_transaction_risk shows `confidence_display`. MLflow run b78f0a3ba3f04ab6b970d1da4744bb9e (experiment /Users/alex.owen@databricks.com/fe_bar_fraud_triage_agent) has the cut-offs, every bucket as a param, and the table as an artifact.

| bucket | lower | upper | rows | fraud | precision | confidence |
| --- | --- | --- | --- | --- | --- | --- |
| decile_01 | 0.0000 | 0.1203 | 9,293 | 47 | 0.0051 | low |
| decile_02 | 0.1203 | 0.1363 | 9,293 | 52 | 0.0056 | low |
| decile_03 | 0.1363 | 0.1468 | 9,292 | 43 | 0.0046 | low |
| decile_04 | 0.1468 | 0.1563 | 9,293 | 60 | 0.0065 | low |
| decile_05 | 0.1563 | 0.1665 | 9,292 | 56 | 0.0060 | low |
| decile_06 | 0.1665 | 0.1786 | 9,293 | 45 | 0.0048 | low |
| decile_07 | 0.1786 | 0.1935 | 9,293 | 51 | 0.0055 | low |
| decile_08 | 0.1935 | 0.2159 | 9,292 | 51 | 0.0055 | low |
| decile_09 | 0.2159 | 0.2660 | 9,293 | 49 | 0.0053 | low |
| decile_10 | 0.2660 | 0.8714 | 5,438 | 240 | 0.0441 | low |
| review_band | 0.8714 | 0.9503 | 3,567 | 897 | 0.2515 | low |
| block_band | 0.9503 | 1.0000 | 288 | 144 | 0.5000 | medium |

(decile_10 holds fewer rows because the test rows at or above the review threshold sit in the two band buckets.)
* VERIFY: TXN-0234209 risk 0.98441, block, auto_block, confidence **medium (observed precision 0.50 in block_band, n=288)**, previously "high". No bucket reaches high. Semantic note: for approve-band transactions "low" means low fraud precision, not low certainty that the transaction is legitimate.
* PII mapping: pii_role_sync.py reads UC group `pii` (nested groups expanded) and, per member, checks whether a Postgres login role exists and whether it is in fraud_pii. DRY RUN: 1 member, alex.owen@databricks.com, role exists, in fraud_pii, action `none`. Applying for my own identity is a no-op, so nothing was applied; an attempted apply call was also blocked by the session's safety check as a permission change. No Postgres roles were created for anyone. The production path to replace the manual membership is a scheduled job running `pii_role_sync.py --apply` under a service principal.

## Notebook output evidence
* The Step 5 commit (c3d825c) contained `lakebase_fgac_validation.ipynb` outputs that were inserted by a script, not produced by running the notebook. `dbutils.notebook.run()` does not write outputs back into the source notebook, which is why fraud_triage_agent.ipynb had none. In this pass, fgac_hardening, lakebase_fgac_validation, lakebase_write_path_validation and fraud_triage_agent are executed in the notebook UI before commit, and their outputs are checked in the GitHub copies after push.

## Other changes
* fraud_triage_agent.ipynb: E.1 now prints a trace span table. The D.3 register cell is guarded with REGISTER=False because re-registering would create v2 and move @champion. **The current @champion v1 still embeds the pre-hardening UC-function tools.** Re-registration needs approval.
