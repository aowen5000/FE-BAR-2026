# App deployment: fe-bar-fraud-triage (Step 9, 2026-11-04)

Workspace: fevm-workshop-guy. Captured 2026-11-05T21:16Z UTC from the Apps API (`GET /api/2.0/apps/fe-bar-fraud-triage`, list deployments). Machine-readable copy: `logs/app_deployment_2026-11-04.json`.

## Identity

| Field | Value |
| --- | --- |
| App URL | https://fe-bar-fraud-triage-7474659392412718.aws.databricksapps.com |
| Service principal name | app-1xzuu6 fe-bar-fraud-triage |
| Service principal ID | 72319122930742 |
| Application (client) ID | 8f239f44-078a-4f8f-90f1-4c1b0bcdc26c |
| Postgres role | `8f239f44-078a-4f8f-90f1-4c1b0bcdc26c` (member of `fraud_triage_agent` only) |
| Source path | /Workspace/Users/alex.owen@databricks.com/FE-BAR-2026-repo/app |
| Active deployment | 01f1d95dc1bd164780340e69688aaa80, SUCCEEDED ("App started successfully"), app RUNNING |
| Framework | Streamlit (`streamlit run app.py`, port from DATABRICKS_APP_PORT, 8000) |

## Declared resources (app-level, attached with `apps update`; referenced by `valueFrom` in app.yaml)

| Key | Type | Target | Permission | Env var |
| --- | --- | --- | --- | --- |
| lakebase-db | postgres | projects/fe-bar-fraud-analytics/branches/production/databases/fe-bar-db (Postgres db fe_bar_db) | CAN_CONNECT_AND_CREATE | LAKEBASE_ENDPOINT (+ auto PGHOST/PGUSER/...) |
| claude-endpoint | serving_endpoint | databricks-claude-sonnet-5-5 | CAN_QUERY | SERVING_ENDPOINT_NAME |
| fraud-genie | genie_space | 01f1d7b464d510b9aa6cde48300787ca | CAN_RUN | GENIE_SPACE_ID |
| fraud-warehouse | sql_warehouse | 9bbc027402111984 | CAN_USE | DATABRICKS_WAREHOUSE_ID |

Thresholds are static env vars read from MLflow run d89beaca8f81447780da60ed2ea7c811 at build time: BLOCK_THRESHOLD=0.9502674433961342, REVIEW_THRESHOLD=0.8714158290727556.

## Deployment history (3 attempts, limit 3)

| # | Deployment ID | Created (UTC) | Result | Cause / action |
| --- | --- | --- | --- | --- |
| 1 | 01f1d955c28a1aacb9283df07a2eaab0 | 20:16:18 | FAILED: App process did not start within 10 minutes | [BUILD] pip backtracked through mlflow 3.18 to 3.1.0 under loose `>=` bounds. Fix: exact pins (commit 9f914df), resolved for Python 3.11 from the registered agent v3 constraints (langgraph<0.4). |
| 2 | 01f1d95bd2961317a2b65949a328bcc5 | 20:59:42 | FAILED: same message | Snapshot had the pinned requirements but stayed "Deployment is pending" with zero log lines; compute was still occupied by attempt 1's resolver. Fix: `apps stop` + `apps start` (no code change). |
| - | 01f1d95d42061f0f908eb7979c465161 | 21:09:58 | CANCELLED | Created by a UI Deploy click while the compute was stopping. |
| 3 | 01f1d95dc1bd164780340e69688aaa80 | 21:13:33 | SUCCEEDED in 1m02s | Started by `apps start`; packages installed in about 40 s; Streamlit serving on 0.0.0.0:8000. |

## Known build warning

pip reported `streamlit 1.38.0 requires protobuf<6,>=3.20, but you have protobuf 7.36.2` (pulled in by mlflow 3.18). The app started and serves; page rendering is confirmed by the browser test in Part D.3.

## Health check from a notebook (Part D.2)

Not possible with workspace authentication: `GET /` and `GET /_stcore/health` with the notebook's workspace token both return 302 to `/oidc/oauth2/v2.0/authorize` (interactive app OAuth). Not worked around; the browser test is the run proof.
