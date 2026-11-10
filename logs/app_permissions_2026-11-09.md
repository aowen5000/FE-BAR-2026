# App permissions: fe-bar-fraud-triage (Step 11)

Workspace fevm-workshop-guy (7474659392412718), step dated 2026-11-09, checks run 2026-11-10 UTC. Conversation 4443667514456316. Branch `step11/2026-11-09_fevm-workshop-guy_conv-4443667514456316`. 100% synthetic data.

The App is the PII tier of the two-tier design (`DECISIONS.md`): it shows exact amounts, including amount > 10000, so only the `pii` group may use it.

## Before (until 2026-11-10 03:48:15 UTC)

Inferred, not captured: the After ACL below minus the one audited change. No earlier ACL read is in the repo logs.

| Principal | Level | Inherited |
| --- | --- | --- |
| alex.owen@databricks.com | CAN_MANAGE | no |
| group admins | CAN_MANAGE | yes, from the workspace apps permissions |

## Change

One `changeAppsAcl` event for `fe-bar-fraud-triage` since 2026-11-03 in `system.access.audit` (service `apps`, workspace 7474659392412718):

| event_time (UTC) | Actor | Request | Status |
| --- | --- | --- | --- |
| 2026-11-10 03:48:15.550 | alex.owen@databricks.com | `[{"group_name": "pii", "permission_level": "CAN_USE"}]` | 200 |

This happened before Part A started, so the Part A capture (04:12:45 UTC) already showed `pii` CAN_USE. It was not made by any step recorded in Parts A to E.

## After (GET /api/2.0/permissions/apps/fe-bar-fraud-triage, 2026-11-10 05:20 UTC)

| Principal | Level | Inherited |
| --- | --- | --- |
| alex.owen@databricks.com | CAN_MANAGE | no |
| group pii | CAN_USE | no |
| group admins | CAN_MANAGE | yes, from the workspace apps permissions |

Validation `validation_notebooks/high_value_triage.ipynb` E.8b: PASS (`pii` CAN_USE present, no `users` grant).

## Notes

* **Admins CAN_MANAGE is inherited and can't be removed on the App.** It comes from the workspace-level apps permissions, not from the App's own ACL, so workspace admins can always open and manage the App.
* **No `users` grant.** Members of `non_pii` who are not in `pii` or `admins` have no App permission.
* **non_pii test user at the App URL: denied, no text evidence.** A second non_pii test user (user ID 76510230734315) was denied at the App URL, observed by the tester and reported by the user on 2026-11-10. The audit log has that user's sign-ins to the App's OAuth client but not the allow/deny decision, and screenshots are not accepted as evidence, so this is not counted as PASS (`genie_agent_benchmark_evidence_logs/non_pii_test_user_2026-11-10.md`).
* **One identity inside the App.** Every user who passes this ACL works as the App's service principal (Postgres role `8f239f44-078a-4f8f-90f1-4c1b0bcdc26c`, member of `fraud_triage_agent`, which is in `fraud_pii`). The ACL is the only per-user control. Per-user OBO is the production fix (`docs/LIMITATIONS.md`).
