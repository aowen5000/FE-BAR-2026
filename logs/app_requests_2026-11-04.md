# App requests: fe-bar-fraud-triage browser-test session (Step 9)

Workspace fevm-workshop-guy. Session: 2026-11-06 00:38 to 03:08 UTC (Step 9 dated 2026-11-04).

## Why this is not the app's stdout log

The app writes one JSON line per Explain / Open case / Genie question to stdout. Its log endpoint (`/logz`) only accepts interactive OAuth: from notebook and agent tooling, `apps logs` fails with "OAuth token exchange failed ... the app /logz endpoints require OAuth and reject PAT auth". I did not work around this. The same requests are recorded below from platform records, which also prove which identity made each call. The raw stdout lines can be exported with `databricks apps logs fe-bar-fraud-triage` from an OAuth CLI session if needed.

## Postgres writes (cases schema, read as fraud_lead)

| Time (UTC) | Table | Row | db_inserted_by | Request |
| --- | --- | --- | --- | --- |
| 2026-11-06 00:38:31 | cases.fraud_cases | case `5af3575c-cda8-47cb-97be-021b26dca000`, TXN-0045116, open, auto_block, created_by `fraud_triage_copilot:agent` | `8f239f44-078a-4f8f-90f1-4c1b0bcdc26c` (app role) | Open case (first click) |
| 2026-11-06 00:38:31 | cases.case_actions | `case_opened` for the same case | `8f239f44-078a-4f8f-90f1-4c1b0bcdc26c` | Open case (first click) |
| after 03:04 | none | no new rows | | Open case repeat clicks (idempotent: the existing case was returned) |

Explain makes no writes (read tools only).

## Genie Conversation API calls by the app service principal (system.access.audit, service aibiGenie)

| First event (UTC) | Action | Conversation ID | Message ID | Events | HTTP |
| --- | --- | --- | --- | --- | --- |
| 2026-11-06 03:07:10 | genieStartConversationMessage | | | 1 | 200 |
| 2026-11-06 03:07:10 | genieGetConversationMessage (polling) | `01f1d98f28021142877f6ea599ede8a1` | `01f1d98f281b1feb86a66e6847689b8b` | 15 | 200 |

Question: "How much fraud did the model catch vs the baseline rule?"

## Warehouse 9bbc027402111984 statements by the app service principal (query history API, user ID 72319122930742)

| Start (UTC) | Statement ID | Source | Status | Duration ms | Statement |
| --- | --- | --- | --- | --- | --- |
| 2026-11-06 03:07:15 | 01f1d98f-2b35-1c8f-8326-da63ea9376e2 | Genie space 01f1d7b4... | FINISHED | 4659 | SELECT strategy, rule_text, fraud_amount_caught, total_fraud_amount FROM fe_bar_lakebase.fraud_dash.baseline_comparison WHERE strategy IN ('model', 'baseline_rule') ORDER BY fraud_amount_caught DESC |
| 2026-11-06 03:07:15 | 01f1d98f-2b4e-1bba-b8db-ab50c6548c82 | Genie space | FINISHED | 2428 | DESCRIBE of the same statement |
| 2026-11-06 03:07:22 | 01f1d98f-2f6b-1435-82e1-42830ceb233c | Genie space | FINISHED | 699 | DESCRIBE of the same statement |
| 2026-11-06 03:07:27 | 01f1d98f-3256-143e-b8dd-335f6ae6dd17 | app (result table) | FINISHED | 5687 | same SELECT, run by the app to render the result table |

No statements by the app service principal on any other object. Before the 03:04 redeploy the app made no Genie calls at all (bug: URL `https://https://...`, fixed in c372cc5).
