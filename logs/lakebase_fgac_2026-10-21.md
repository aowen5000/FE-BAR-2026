# Lakebase FGAC Log — 2026-10-21

## Roles Created
| Role | Type | PII Member | Purpose |
|------|------|------------|--------|
| fraud_pii | NOLOGIN group | — (is the PII group) | Mirrors UC pii group |
| fraud_analyst | NOLOGIN group | No | Non-pii analyst persona |
| fraud_lead | NOLOGIN group | Yes (member of fraud_pii) | Head of Fraud Ops |
| fraud_triage_agent | NOLOGIN group | Yes (member of fraud_pii) | Agent's governed role |

Note: alex.owen@databricks.com granted membership in all 4 roles for testing. Membership is managed manually in Postgres for this build.

## Grants
- USAGE on schemas fraud_gov, fraud, cases to fraud_analyst, fraud_lead, fraud_triage_agent
- SELECT on fraud_gov.* views to all three roles
- SELECT on cases.fraud_cases and cases.case_actions to all three roles
- INSERT on cases.fraud_cases and cases.case_actions to fraud_triage_agent only
- UPDATE (status, updated_at) on cases.fraud_cases to fraud_analyst only
- No direct SELECT on fraud.* synced tables to any governed role

## Governed Views (fraud_gov schema)
| View | Row Rule | Column Rule |
|------|----------|------------|
| fraud_gov.txn_risk_current | amount > 10000 hidden unless fraud_pii member | — |
| fraud_gov.txn_features | amount > 10000 hidden unless fraud_pii member | amt_to_monthly_spend NULL unless fraud_pii |
| fraud_gov.customer_risk_profile | None | None |

All views use security_barrier = true.

## RLS Policies on Case Tables
| Table | Role | SELECT | INSERT | UPDATE | DELETE |
|-------|------|--------|--------|--------|--------|
| fraud_cases | fraud_lead | All rows | — | — | — |
| fraud_cases | fraud_analyst | analyst_review + amount <= 10000 | — | status, updated_at only | — |
| fraud_cases | fraud_triage_agent | All rows | created_by LIKE 'fraud_triage_copilot%' | — | — |
| case_actions | fraud_lead | All rows | — | — | — |
| case_actions | fraud_analyst | Parent case visible | — | — | — |
| case_actions | fraud_triage_agent | All rows | actor LIKE 'fraud_triage_copilot%' | — | — |

FORCE ROW LEVEL SECURITY enabled on both tables.

## Before/After Picture (Part A.5)

### Before (no FGAC)
| Path | Total Rows | High Amount | Non-null amt_to_monthly_spend |
|------|-----------|-------------|-------------------------------|
| UC fe_bar_lakebase.fraud.txn_features | 464,632 | 751 | 431,471 |
| Direct Postgres fraud.txn_features | 464,632 | 751 | 431,471 |
| UC silver (workshop_guy_catalog.fe_bar_a0) | Governed by row filter + column mask | — | — |

### After (with FGAC)
| Role | fraud_gov.txn_features Rows | High Amount | Non-null amt_to_spend | Cases Visible |
|------|----------------------------|-------------|----------------------|---------------|
| fraud_analyst | 463,881 | 0 | 0 | 100 |
| fraud_lead | 464,632 | 751 | 431,471 | 104 |
| fraud_triage_agent | 464,632 | 751 | 431,471 | 104 |

## Deny Test Results (all DENIED as expected)
| Role | Operation | Error |
|------|-----------|-------|
| fraud_analyst | INSERT case | permission denied for table fraud_cases |
| fraud_analyst | UPDATE notes | permission denied for table fraud_cases |
| fraud_triage_agent | UPDATE case | permission denied for table fraud_cases |
| fraud_triage_agent | DELETE case | permission denied for table fraud_cases |
| fraud_triage_agent | INSERT wrong created_by | new row violates row-level security policy |
| fraud_analyst | direct SELECT fraud.txn_features | permission denied for table txn_features |
| fraud_lead | direct SELECT fraud.txn_features | permission denied for table txn_features |
| fraud_triage_agent | direct SELECT fraud.txn_features | permission denied for table txn_features |

## Allow Test Results
- fraud_triage_agent INSERT via LakebaseCases: ALLOWED (case 2153e489)
- fraud_analyst UPDATE status on visible case: ALLOWED
- Cleanup: case closed as superuser

## Latency (200 PK lookups on fraud_gov.txn_risk_current as fraud_triage_agent)
| Metric | Value |
|--------|-------|
| p50 | 3.82 ms |
| p95 | 5.81 ms |
| p99 | 7.98 ms |
| min | 2.43 ms |
| max | 8.05 ms |

Conclusion: security_barrier views do not break the single-digit ms latency goal.
