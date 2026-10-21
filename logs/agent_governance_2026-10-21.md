# Agent Governance Log — 2026-10-21

## UC vs Postgres FGAC Enforcement

### A.5 Before Picture
- UC fe_bar_lakebase.fraud.txn_features: 464,632 rows visible, 751 high-amount rows visible, 431,471 non-null amt_to_monthly_spend
- Direct Postgres fraud.txn_features: Same (no RLS before FGAC setup)
- Finding: UC FGAC (row filter/column mask on silver tables) does NOT propagate to Lakebase synced tables

### B.6 After Picture — fraud_gov views through UC
- fe_bar_lakebase.fraud_gov.txn_features via UC: 463,881 rows (751 hidden), 0 high-amount, 0 non-null amt_to_monthly_spend
- Finding: fraud_gov views ARE visible through UC. However, pg_has_role() always returns FALSE through UC because UC queries use a Postgres system role (databricks_gateway/databricks_reader_*), not the user's personal Databricks role. Therefore, the views always apply the non-pii filter path through UC, regardless of the user's UC group membership.

## Why create_fraud_case is an Agent-Side Python Tool
UC functions cannot obtain Lakebase OAuth credentials or open Postgres connections. When a UC Python function runs on a Databricks serverless warehouse, it executes in a restricted environment without access to `WorkspaceClient.postgres.generate_database_credential()`. Attempting to import `psycopg` or call Lakebase from a UC function fails with import errors or missing credentials.

Therefore:
- get_transaction_risk, explain_top_signals, get_customer_history: UC SQL functions (read from Lakebase via external connection through the Lakehouse Federation / MANAGED_ONLINE_CATALOG mechanism)
- create_fraud_case: Agent-side Python tool wrapping LakebaseCases(pg_role='fraud_triage_agent'), which uses generate_database_credential() + psycopg directly

## Synced-Table RLS Limitation
The synced tables (fraud.txn_features, fraud.txn_risk_current, fraud.customer_risk_profile) are owned by the sync pipeline's internal writer roles (databricks_writer_*). Postgres ENABLE/FORCE ROW LEVEL SECURITY requires the table owner or a superuser. These tables are managed by the sync pipeline and modifying their RLS would break the sync. Therefore, FGAC on synced tables uses security_barrier views in fraud_gov instead of RLS on the base tables.

## Case Tables Through UC
FORCE ROW LEVEL SECURITY on cases.fraud_cases and cases.case_actions means UC queries (which run as Postgres system roles without any RLS policy) return 0 rows. This is intentional: the case tables are access-controlled exclusively through direct Postgres connections with SET ROLE. The get_customer_history UC function joins to cases.fraud_cases but returns no existing_cases rows through UC for this reason.

## Prior Fraud Cases Table
Used: workshop_guy_catalog.fe_bar_a0.fact_prior_fraud_cases_silver
Columns: case_id, customer_id, txn_id, fraud_type, investigation_outcome, recovery_amount, resolution_date
