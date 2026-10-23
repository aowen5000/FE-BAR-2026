# dashboard_validation run evidence (2026-10-22)

Workspace: fevm-workshop-guy. Genie conversation ID: 1835980093459154. Date: 2026-10-22 (run timestamps are UTC, 2026-10-23).

* Job run: 659281894932228 (one-time submit, serverless), task run 403680627357199 (attempt 1, SUCCESS)
* Task start 2026-10-23 02:22:28 UTC, end 2026-10-23 02:43:20 UTC
* Run page: https://fevm-workshop-guy.cloud.databricks.com/?o=7474659392412718#job/697188011427776/run/659281894932228
* Notebook: validation_notebooks/dashboard_validation.ipynb (workspace object 2932538792700906)
* The first attempt (task 1111349178305485) failed with SIGABRT in the setup cell; serverless retried automatically.
* A second submitted run, 1080711831453220, was cancelled on the user's instruction before its D.2 cell, so it created no case.
* This file was generated from the run's own exported notebook model (jobs export-run). The raw export is dashboard_validation_run_659281894932228.html in this folder.

## Cell 1: Overview (finished)

```python
%md
# Step 6: Fraud Ops AI/BI dashboard (Layer 5) reading live from Lakebase

Validation and live-read proof for the dashboard **FE Bar Fraud Ops: Triage & Action** (dashboard ID `01f1ce7f835a1e81b05ebb664bf0994c`, warehouse `9bbc027402111984`).

* Part A: pre-flight checks (stop if any fail)
* Part B: `fraud_dash` read layer in Lakebase (`lakebase_dashboard.sql`): apply, row counts, deny tests, TXN-0234209, latency through UC
* Part D: every dashboard dataset through the warehouse Statement Execution API, live-read proof (agent writes a case, no sync/job in between), TXN-0234209 end-to-end trace

Workspace fevm-workshop-guy, serverless compute. All timestamps are UTC (Postgres session TZ = GMT, warehouse `current_date()` = UTC).
```

## Cell 2: Install libraries (finished)

```python
# Same libraries as fraud_triage_agent.ipynb (agent for Part D.2) plus psycopg for direct Postgres checks
%pip install -q databricks-langchain "langgraph>=0.3,<0.4" databricks-agents "psycopg[binary]>=3.1.0" pydantic databricks-ai-search
dbutils.library.restartPython()
```

Output:

```text
Note: you may need to restart the kernel using %restart_python or dbutils.library.restartPython() to use updated packages.
```

## Cell 3: Setup: constants and helpers (finished)

```python
import os, sys, json, time, statistics, datetime as dt
sys.path.insert(0, os.path.dirname(os.getcwd()))   # repo root (one level above validation_notebooks/)
REPO = os.path.dirname(os.getcwd())

import mlflow
from databricks.sdk import WorkspaceClient
from databricks.sdk.service.sql import StatementParameterListItem
from lakebase_cases import LakebaseCases

w = WorkspaceClient()
WAREHOUSE_ID = "9bbc027402111984"
DASH_ID = "01f1ce7f835a1e81b05ebb664bf0994c"
UC = "fe_bar_lakebase"
MLFLOW_RUN = "d89beaca8f81447780da60ed2ea7c811"
JOB_ID = 1115396029932218
SYNC_PIPELINE = "f8690359-4bb1-45b9-8fdb-5bd892239db2"
TRACED_TXN = "TXN-0234209"
LOG_DATE = "2026-10-22"
FRAUD_DASH_VIEWS = ["case_summary", "case_actions_daily", "score_distribution", "exposure", "baseline_comparison", "triage_queue"]

def now():
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%S.%f")[:-3] + " UTC"

def fmt_table(cols, rows, max_w=60):
    """Plain-text table (markdown pipe style) so outputs are readable in the committed .ipynb."""
    def s(v):
        v = "NULL" if v is None else str(v)
        return v if len(v) <= max_w else v[: max_w - 3] + "..."
    rows = [[s(v) for v in r] for r in rows]
    out = ["| " + " | ".join(cols) + " |", "| " + " | ".join("---" for _ in cols) + " |"]
    out += ["| " + " | ".join(r) + " |" for r in rows]
    return "\n".join(out)

def show(cols, rows, title=None, max_w=60):
    if title: print(f"\n### {title}")
    print(fmt_table(cols, rows, max_w))

# --- Postgres (direct, identity-aware via SET ROLE) ---------------------------
admin = LakebaseCases()                       # alex.owen login, no SET ROLE
lead = LakebaseCases(pg_role="fraud_lead")    # SET ROLE fraud_lead

def pg(conn_obj, sql, params=()):
    rows = conn_obj.query(sql, params)
    return (list(rows[0].keys()) if rows else []), [list(r.values()) for r in rows]

# --- UC on serverless (Spark) -------------------------------------------------
def uc_rows(sql, args=None):
    df = spark.sql(sql, args=args) if args else spark.sql(sql)
    rows = df.collect()
    return df.columns, [list(r) for r in rows]

# --- Warehouse Statement Execution API (same engine as the dashboard) ----------
def wh(sql, params=None):
    t0 = time.time()
    r = w.statement_execution.execute_statement(warehouse_id=WAREHOUSE_ID, statement=sql, wait_timeout="50s", parameters=params)
    while r.status.state.value in ("PENDING", "RUNNING"):
        time.sleep(1); r = w.statement_execution.get_statement(r.statement_id)
    ms = (time.time() - t0) * 1000
    if r.status.state.value != "SUCCEEDED":
        raise RuntimeError(f"{r.status.state.value}: {r.status.error.message if r.status.error else ''}")
    cols = [c.name for c in r.manifest.schema.columns]
    return cols, (r.result.data_array or []) if r.result else [], ms, r.statement_id

# --- Dashboard dataset SQL, read from the dashboard definition itself ----------
dash_def = json.loads(w.lakeview.get(DASH_ID).serialized_dashboard)
DATASETS = {d["name"]: {"display": d["displayName"], "sql": "".join(d["queryLines"]).strip(), "params": d.get("parameters", [])} for d in dash_def["datasets"]}

def bind_multi(sql, action=(), queue=(), status=()):
    """MULTI (array) parameters of ds_triage, bound the way the dashboard binds them (empty array = no filter).
    Only the parameter markers are replaced; the rest of the SQL is the dashboard's text."""
    arr = lambda xs: "array(" + ", ".join("'" + x + "'" for x in xs) + ")" if xs else "array()"
    return sql.replace(":action_f", arr(action)).replace(":queue_f", arr(queue)).replace(":status_f", arr(status))

def dataset_call(name, txn_id="ALL", **multi):
    """Return (sql, statement-API params, spark args) for a dashboard dataset."""
    sql = DATASETS[name]["sql"]
    if name == "ds_triage":
        return bind_multi(sql, **multi), [StatementParameterListItem(name="txn_id_f", value=txn_id, type="STRING")], {"txn_id_f": txn_id}
    return sql, None, None

print(f"[{now()}] setup done. Dashboard '{w.lakeview.get(DASH_ID).display_name}' has {len(DATASETS)} datasets: {list(DATASETS)}")
```

Output:

```text
[2026-10-23 02:24:04.834 UTC] setup done. Dashboard 'FE Bar Fraud Ops: Triage & Action' has 10 datasets: ['ds_kpi_cases', 'ds_model_vs_baseline', 'ds_score_dist', 'ds_cases_daily', 'ds_actions_daily', 'ds_triage', 'ds_triage_options', 'ds_recent_cases', 'ds_calibration', 'ds_exposure']
```

## Cell 4: A.1 Identity and A.2 UC row counts (before picture) (finished)

```python
print(f"[{now()}] Part A pre-flight")
cols, rows = uc_rows("SELECT current_user() AS current_user, is_account_group_member('pii') AS in_pii")
show(cols, rows, "A.1 current_user / pii membership (UC, serverless)")

counts = []
for t in ["fraud_gov.txn_risk_current", "fraud.txn_risk_current", "cases.fraud_cases"]:
    n = uc_rows(f"SELECT count(*) AS n FROM {UC}.{t}")[1][0][0]
    counts.append([f"{UC}.{t}", n])
show(["object (through UC)", "rows"], counts, "A.2 row counts through UC")
UC_CASES_BEFORE = counts[2][1]
assert UC_CASES_BEFORE == 0, "STOP: fe_bar_lakebase.cases.fraud_cases is no longer 0 rows through UC"
print(f"\nPASS: cases through UC = {UC_CASES_BEFORE} (RLS, reader role has no policy). This is the 'before' picture for Part B.")
```

Output:

```text
[2026-10-23 02:24:05.184 UTC] Part A pre-flight

### A.1 current_user / pii membership (UC, serverless)
| current_user | in_pii |
| --- | --- |
| alex.owen@databricks.com | True |

### A.2 row counts through UC
| object (through UC) | rows |
| --- | --- |
| fe_bar_lakebase.fraud_gov.txn_risk_current | 463881 |
| fe_bar_lakebase.fraud.txn_risk_current | 464632 |
| fe_bar_lakebase.cases.fraud_cases | 0 |

PASS: cases through UC = 0 (RLS, reader role has no policy). This is the 'before' picture for Part B.
```

## Cell 5: A.3 Cases in Postgres as fraud_lead (finished)

```python
cols, rows = pg(lead, "SELECT current_user, session_user")
show(cols, rows, "A.3 Postgres identity (SET ROLE fraud_lead)")
cols, rows = pg(lead, "SELECT assigned_queue, status, count(*) AS cases FROM cases.fraud_cases GROUP BY 1, 2 ORDER BY 1, 2")
show(cols, rows, "A.3 cases by assigned_queue and status (fraud_lead)")
LEAD_TOTAL_BEFORE = sum(r[2] for r in rows)
cols, rows = pg(lead, "SELECT current_date AS today_utc, count(*) FILTER (WHERE created_at::date = current_date) AS created_today, count(*) AS total FROM cases.fraud_cases")
show(cols, rows, "A.3 cases created today (fraud_lead)")
cols, rows = pg(lead, "SELECT case_id, txn_id, status, assigned_queue, recommended_action, created_by, created_at, db_inserted_by FROM cases.fraud_cases WHERE txn_id = %s", (TRACED_TXN,))
show(cols, rows, f"A.3 case row for {TRACED_TXN} (fraud_lead)")
assert rows and str(rows[0][0]).startswith("2319d4b7"), "STOP: traced case 2319d4b7 not found"
```

Output:

```text

### A.3 Postgres identity (SET ROLE fraud_lead)
| current_user | session_user |
| --- | --- |
| fraud_lead | alex.owen@databricks.com |

### A.3 cases by assigned_queue and status (fraud_lead)
| assigned_queue | status | cases |
| --- | --- | --- |
| analyst_review | closed | 159 |
| auto_block | closed | 4 |
| auto_block | open | 7 |

### A.3 cases created today (fraud_lead)
| today_utc | created_today | total |
| --- | --- | --- |
| 2026-10-23 | 1 | 170 |

### A.3 case row for TXN-0234209 (fraud_lead)
| case_id | txn_id | status | assigned_queue | recommended_action | created_by | created_at | db_inserted_by |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 2319d4b7-bea3-412b-ba6b-8325e1a7a71d | TXN-0234209 | open | auto_block | block | fraud_triage_copilot:agent | 2026-10-21 00:02:21.031588+00:00 | alex.owen@databricks.com |
```

## Cell 6: A.4 UC reader role: name, attributes, and proof it is the UC identity (finished)

```python
import threading
cols, rows = pg(admin, "SELECT oid, datname FROM pg_database WHERE datname = current_database()")
READER = f"databricks_reader_{rows[0][0]}"
print(f"fe_bar_db oid = {rows[0][0]}  ->  UC reader role = {READER}")
cols, rows = pg(admin, """SELECT r.rolname, r.rolsuper, r.rolbypassrls, r.rolcanlogin, r.rolinherit,
                                 coalesce((SELECT string_agg(m.rolname, ', ') FROM pg_auth_members am JOIN pg_roles m ON m.oid = am.roleid WHERE am.member = r.oid), '(none)') AS member_of
                          FROM pg_roles r WHERE r.rolname = %s""", (READER,))
show(cols, rows, "A.4 reader role attributes")
assert rows and rows[0][1] is False and rows[0][2] is False and rows[0][5] == "(none)", "STOP: reader role has elevated attributes or memberships"

# Proof: run a UC query in a background thread and sample pg_stat_activity while it executes.
seen, res = set(), []
th = threading.Thread(target=lambda: res.append(uc_rows(f"SELECT count(*) AS n, sum(amount) AS s FROM {UC}.fraud.txn_features")[1]))
th.start()
while th.is_alive():
    for r in admin.query("SELECT usename, application_name, left(query, 90) AS q FROM pg_stat_activity WHERE datname = 'fe_bar_db' AND pid <> pg_backend_pid() AND usename <> session_user AND query ILIKE '%%txn_features%%'"):
        seen.add((r["usename"], r["application_name"], r["q"].strip()))
    time.sleep(0.2)
th.join()
show(["usename (Postgres session serving the UC query)", "application_name", "query pushed down by UC"], sorted(seen), "A.4 pg_stat_activity sampled during a UC query")
assert any(s[0] == READER for s in seen), "could not observe the UC session"
print(f"\nCONFIRMED: UC queries on {UC} run in Postgres as {READER} (observed in pg_stat_activity while the UC query ran, "
      f"from the JDBC driver, with the pushed-down SQL). UC result: {res[0]}")
```

Output:

```text
fe_bar_db oid = 17063  ->  UC reader role = databricks_reader_17063

### A.4 reader role attributes
| rolname | rolsuper | rolbypassrls | rolcanlogin | rolinherit | member_of |
| --- | --- | --- | --- | --- | --- |
| databricks_reader_17063 | False | False | True | True | (none) |

### A.4 pg_stat_activity sampled during a UC query
| usename (Postgres session serving the UC query) | application_name | query pushed down by UC |
| --- | --- | --- |
| databricks_reader_17063 | PostgreSQL JDBC Driver | SELECT COUNT(*),SUM("amount") FROM "fraud"."txn_features" |

CONFIRMED: UC queries on fe_bar_lakebase run in Postgres as databricks_reader_17063 (observed in pg_stat_activity while the UC query ran, from the JDBC driver, with the pushed-down SQL). UC result: [[464632, 101444581.35999942]]
```

## Cell 7: A.5 Warehouse can read fe_bar_lakebase (finished)

```python
cols, rows, ms, sid = wh(f"SELECT count(*) AS n, current_user() AS run_as FROM {UC}.fraud_gov.txn_risk_current")
show(cols, rows, f"A.5 warehouse {WAREHOUSE_ID} SELECT on {UC}.fraud_gov.txn_risk_current ({ms:.0f} ms, statement {sid})")
assert int(rows[0][0]) > 0, "STOP: warehouse returned no rows"
print("PASS: all Part A pre-flight checks passed")
```

Output:

```text

### A.5 warehouse 9bbc027402111984 SELECT on fe_bar_lakebase.fraud_gov.txn_risk_current (10094 ms, statement 01f1ce88-e51b-1b9b-a898-97c3ed1e7016)
| n | run_as |
| --- | --- |
| 463881 | alex.owen@databricks.com |
PASS: all Part A pre-flight checks passed
```

## Cell 8: B.0 Apply lakebase_dashboard.sql, load thresholds from MLflow, inspect objects (finished)

```python
print(f"[{now()}] Part B")
policies_before = pg(admin, "SELECT tablename, policyname, cmd, roles::text, qual, with_check FROM pg_policies WHERE schemaname = 'cases' ORDER BY 1, 2")[1]

# Idempotent apply (CREATE IF NOT EXISTS / CREATE OR REPLACE / re-runnable GRANTs)
dash_sql = open(os.path.join(REPO, "lakebase_dashboard.sql")).read()
conn = admin._get_conn()
with conn.cursor() as cur:
    cur.execute(dash_sql)
conn.commit()
print(f"[{now()}] applied lakebase_dashboard.sql ({len(dash_sql)} chars)")

# lakebase_fgac.sql must carry an identical copy so a fresh rebuild includes fraud_dash
fgac = open(os.path.join(REPO, "lakebase_fgac.sql")).read()
block = fgac.split("-- >>> BEGIN lakebase_dashboard.sql\n")[1].split("-- <<< END lakebase_dashboard.sql\n")[0]
END_MARK = "-- ============================================================\n-- END\n-- ============================================================\n"
assert block == dash_sql.replace(END_MARK, "").rstrip() + "\n", "lakebase_fgac.sql B.4 block differs from lakebase_dashboard.sql"
print("PASS: lakebase_fgac.sql B.4 block is identical to lakebase_dashboard.sql")

# Thresholds: read from the MLflow run, never hardcoded
p = mlflow.get_run(MLFLOW_RUN).data.params
BLOCK_T, REVIEW_T = float(p["block_threshold"]), float(p["review_threshold"])
with conn.cursor() as cur:
    cur.execute("""INSERT INTO fraud_dash.model_thresholds (model_run_id, block_threshold, review_threshold)
                   VALUES (%s, %s, %s)
                   ON CONFLICT (model_run_id) DO UPDATE SET block_threshold = EXCLUDED.block_threshold,
                       review_threshold = EXCLUDED.review_threshold, loaded_at = now()""", (MLFLOW_RUN, BLOCK_T, REVIEW_T))
conn.commit()
show(*pg(admin, "SELECT model_run_id, block_threshold, review_threshold, loaded_at FROM fraud_dash.model_thresholds"), f"fraud_dash.model_thresholds (from MLflow run {MLFLOW_RUN})")

cols, rows = pg(admin, """SELECT c.relname AS object, CASE c.relkind WHEN 'v' THEN 'view' WHEN 'r' THEN 'table' END AS kind,
                                 pg_get_userbyid(c.relowner) AS owner, coalesce(array_to_string(c.reloptions, ','), '') AS options,
                                 has_table_privilege(%s, c.oid, 'SELECT') AS reader_select
                          FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                          WHERE n.nspname = 'fraud_dash' AND c.relkind IN ('v', 'r') ORDER BY 1""", (READER,))
show(cols, rows, "fraud_dash objects")
policies_after = pg(admin, "SELECT tablename, policyname, cmd, roles::text, qual, with_check FROM pg_policies WHERE schemaname = 'cases' ORDER BY 1, 2")[1]
assert policies_before == policies_after, "RLS policies changed!"
print(f"PASS: the {len(policies_after)} existing RLS policies on cases.* are unchanged (no new policy added)")
```

Output:

```text
[2026-10-23 02:24:48.106 UTC] Part B
[2026-10-23 02:24:49.124 UTC] applied lakebase_dashboard.sql (12395 chars)
PASS: lakebase_fgac.sql B.4 block is identical to lakebase_dashboard.sql

### fraud_dash.model_thresholds (from MLflow run d89beaca8f81447780da60ed2ea7c811)
| model_run_id | block_threshold | review_threshold | loaded_at |
| --- | --- | --- | --- |
| d89beaca8f81447780da60ed2ea7c811 | 0.9502674433961342 | 0.8714158290727556 | 2026-10-23 02:24:49.420485+00:00 |

### fraud_dash objects
| object | kind | owner | options | reader_select |
| --- | --- | --- | --- | --- |
| baseline_comparison | view | fraud_lead | security_barrier=true | True |
| case_actions_daily | view | fraud_lead | security_barrier=true | True |
| case_summary | view | fraud_lead | security_barrier=true | True |
| exposure | view | fraud_lead | security_barrier=true | True |
| model_thresholds | table | alex.owen@databricks.com |  | True |
| score_distribution | view | fraud_lead | security_barrier=true | True |
| triage_queue | view | fraud_lead | security_barrier=true | True |
PASS: the 9 existing RLS policies on cases.* are unchanged (no new policy added)
```

## Cell 9: B.1 Row counts through UC and case count vs fraud_lead (finished)

```python
rows = []
for v in FRAUD_DASH_VIEWS + ["model_thresholds"]:
    rows.append([f"{UC}.fraud_dash.{v}", uc_rows(f"SELECT count(*) FROM {UC}.fraud_dash.{v}")[1][0][0]])
show(["object (through UC, as " + READER + ")", "rows"], rows, "B.1 fraud_dash row counts through UC")

DASH_CASES = uc_rows(f"SELECT count(*) FROM {UC}.fraud_dash.case_summary")[1][0][0]
LEAD_CASES = pg(lead, "SELECT count(*) FROM cases.fraud_cases")[1][0][0]
cols, hi = pg(lead, """SELECT c.case_id, c.txn_id, c.status, c.assigned_queue, tf.amount
                       FROM cases.fraud_cases c JOIN fraud_gov.txn_features tf ON tf.txn_id = c.txn_id
                       WHERE tf.amount > 10000 ORDER BY tf.amount DESC""")
show(["source", "cases"], [["fraud_dash.case_summary through UC", DASH_CASES], ["cases.fraud_cases in Postgres as fraud_lead", LEAD_CASES], ["difference", LEAD_CASES - DASH_CASES]], "B.1 case count comparison")
show(cols, hi, "High-amount cases (amount > 10000) visible to fraud_lead, excluded from fraud_dash")
assert LEAD_CASES - DASH_CASES == len(hi), "difference is not fully explained by high-amount exclusions"
print(f"\nPASS: the difference of {LEAD_CASES - DASH_CASES} is exactly the {len(hi)} high-amount cases (amount > 10000 via fraud_gov.txn_features).")
```

Output:

```text

### B.1 fraud_dash row counts through UC
| object (through UC, as databricks_reader_17063) | rows |
| --- | --- |
| fe_bar_lakebase.fraud_dash.case_summary | 165 |
| fe_bar_lakebase.fraud_dash.case_actions_daily | 7 |
| fe_bar_lakebase.fraud_dash.score_distribution | 31 |
| fe_bar_lakebase.fraud_dash.exposure | 6 |
| fe_bar_lakebase.fraud_dash.baseline_comparison | 2 |
| fe_bar_lakebase.fraud_dash.triage_queue | 24201 |
| fe_bar_lakebase.fraud_dash.model_thresholds | 1 |

### B.1 case count comparison
| source | cases |
| --- | --- |
| fraud_dash.case_summary through UC | 165 |
| cases.fraud_cases in Postgres as fraud_lead | 170 |
| difference | 5 |

### High-amount cases (amount > 10000) visible to fraud_lead, excluded from fraud_dash
| case_id | txn_id | status | assigned_queue | amount |
| --- | --- | --- | --- | --- |
| 0a4ac09a-07db-4bd2-a7be-0a3212083825 | TXN-0256919 | closed | analyst_review | 10903.33 |
| f14b5762-f7f8-4a9b-a61c-eab0531d9612 | TXN-0142590 | closed | auto_block | 10877.1 |
| abda6590-c9a4-4df2-a9e4-9f2373d6e904 | TXN-0142590 | closed | auto_block | 10877.1 |
| d7176277-1f2f-4f99-8323-c82240a9279e | TXN-0142590 | closed | auto_block | 10877.1 |
| d9f9ff83-b98e-45e6-a4e7-7570fcbf1def | TXN-0068738 | closed | analyst_review | 10157.27 |

PASS: the difference of 5 is exactly the 5 high-amount cases (amount > 10000 via fraud_gov.txn_features).
```

## Cell 10: B.2 Deny tests (finished)

```python
results = []
def expect(name, fn, ok_if):
    try:
        out = fn(); verdict = "PASS" if ok_if(out, None) else "FAIL"; detail = str(out)[:160]
    except Exception as e:
        verdict = "PASS" if ok_if(None, e) else "FAIL"; detail = (type(e).__name__ + ": " + str(e).split("\n")[0])[:160]
    results.append([name, verdict, detail])

zero_rows = lambda out, e: e is None and out[1] in ([], [[0]])
errored = lambda out, e: e is not None

# 1. raw case table through UC still returns nothing (RLS: reader has no policy)
expect("UC: SELECT count(*) FROM cases.fraud_cases", lambda: uc_rows(f"SELECT count(*) FROM {UC}.cases.fraud_cases"), zero_rows)
expect("UC: SELECT notes, db_inserted_by FROM cases.fraud_cases", lambda: uc_rows(f"SELECT notes, db_inserted_by FROM {UC}.cases.fraud_cases"), zero_rows)
expect("UC: SELECT notes, db_inserted_by FROM cases.case_actions", lambda: uc_rows(f"SELECT db_inserted_by FROM {UC}.cases.case_actions"), zero_rows)
# 2. the dashboard layer does not expose notes / created_by / db_inserted_by
for col in ["notes", "created_by", "db_inserted_by"]:
    expect(f"UC: SELECT {col} FROM fraud_dash.case_summary", lambda col=col: uc_rows(f"SELECT {col} FROM {UC}.fraud_dash.case_summary"), errored)
# 3. writes through UC are rejected (statements are no-ops even if they were allowed)
expect("UC: INSERT INTO fraud_dash.model_thresholds", lambda: uc_rows(f"INSERT INTO {UC}.fraud_dash.model_thresholds VALUES ('deny_test', 0, 0, TIMESTAMP'2000-01-01')"), errored)
expect("UC: UPDATE cases.fraud_cases SET notes = notes", lambda: uc_rows(f"UPDATE {UC}.cases.fraud_cases SET notes = notes WHERE txn_id = '{TRACED_TXN}'"), errored)
expect("UC: DELETE FROM fraud_dash.case_summary WHERE false", lambda: uc_rows(f"DELETE FROM {UC}.fraud_dash.case_summary WHERE 1 = 0"), errored)
show(["deny test", "result", "detail"], results, "B.2 deny tests through UC", max_w=160)
# clean-up guard: if the INSERT had somehow succeeded, remove the row and fail loudly
if pg(admin, "SELECT count(*) FROM fraud_dash.model_thresholds WHERE model_run_id = 'deny_test'")[1][0][0]:
    raise AssertionError("UC INSERT succeeded - investigate")

# 4. Postgres catalog: the reader role has no write privilege anywhere and no column access via fraud_dash
cols, rows = pg(admin, """SELECT n.nspname AS schema, count(*) AS relations,
         count(*) FILTER (WHERE has_table_privilege(%s, c.oid, 'SELECT')) AS reader_select,
         count(*) FILTER (WHERE has_table_privilege(%s, c.oid, 'INSERT') OR has_table_privilege(%s, c.oid, 'UPDATE')
                           OR has_table_privilege(%s, c.oid, 'DELETE') OR has_table_privilege(%s, c.oid, 'TRUNCATE')) AS reader_write
       FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname IN ('cases', 'fraud', 'fraud_gov', 'fraud_dash') AND c.relkind IN ('r', 'v', 'p')
       GROUP BY 1 ORDER BY 1""", (READER,) * 5)
show(cols, rows, f"B.2 Postgres privileges of {READER}")
assert all(r[3] == 0 for r in rows), "reader role has a write privilege"
cols, rows = pg(admin, """SELECT a.attname AS column, has_column_privilege(%s, 'cases.fraud_cases', a.attname, 'SELECT') AS reader_column_select
                          FROM pg_attribute a WHERE a.attrelid = 'cases.fraud_cases'::regclass AND a.attname IN ('notes', 'created_by', 'db_inserted_by')""", (READER,))
show(cols, rows, "B.2 FLAG: pre-existing table-level SELECT of the reader on cases.fraud_cases (rows still hidden by FORCE RLS)")
cols, rows = pg(admin, "SELECT defaclrole::regrole::text AS grantor, defaclnamespace::regnamespace::text AS schema, defaclacl::text AS default_acl FROM pg_default_acl")
show(cols, rows, "Lakebase platform default privileges (source of reader SELECT on new objects)", max_w=120)
assert all(r[1] == "PASS" for r in results), "a deny test failed"
print("PASS: all deny tests")
```

Output:

```text

### B.2 deny tests through UC
| deny test | result | detail |
| --- | --- | --- |
| UC: SELECT count(*) FROM cases.fraud_cases | PASS | (['count(*)'], [[0]]) |
| UC: SELECT notes, db_inserted_by FROM cases.fraud_cases | PASS | (['notes', 'db_inserted_by'], []) |
| UC: SELECT notes, db_inserted_by FROM cases.case_actions | PASS | (['db_inserted_by'], []) |
| UC: SELECT notes FROM fraud_dash.case_summary | PASS | AnalysisException: [UNRESOLVED_COLUMN.WITH_SUGGESTION] A column, variable, or function parameter with name `notes` cannot be resolved. Did you mean one of the f |
| UC: SELECT created_by FROM fraud_dash.case_summary | PASS | AnalysisException: [UNRESOLVED_COLUMN.WITH_SUGGESTION] A column, variable, or function parameter with name `created_by` cannot be resolved. Did you mean one of  |
| UC: SELECT db_inserted_by FROM fraud_dash.case_summary | PASS | AnalysisException: [UNRESOLVED_COLUMN.WITH_SUGGESTION] A column, variable, or function parameter with name `db_inserted_by` cannot be resolved. Did you mean one |
| UC: INSERT INTO fraud_dash.model_thresholds | PASS | UnknownException: (com.databricks.sql.managedcatalog.acl.UnauthorizedAccessException) PERMISSION_DENIED: Only READ credentials can be retrieved for foreign tabl |
| UC: UPDATE cases.fraud_cases SET notes = notes | PASS | AnalysisException: [UC_COMMAND_NOT_SUPPORTED.WITHOUT_RECOMMENDATION] The command(s): UpdateTable are not supported in Unity Catalog.  SQLSTATE: 0AKUC; |
| UC: DELETE FROM fraud_dash.case_summary WHERE false | PASS | UnknownException: (com.databricks.sql.managedcatalog.acl.UnauthorizedAccessException) PERMISSION_DENIED: Only READ credentials can be retrieved for foreign tabl |

### B.2 Postgres privileges of databricks_reader_17063
| schema | relations | reader_select | reader_write |
| --- | --- | --- | --- |
| cases | 2 | 2 | 0 |
| fraud | 4 | 4 | 0 |
| fraud_dash | 7 | 7 | 0 |
| fraud_gov | 4 | 4 | 0 |

### B.2 FLAG: pre-existing table-level SELECT of the reader on cases.fraud_cases (rows still hidden by FORCE RLS)
| column | reader_column_select |
| --- | --- |
| created_by | True |
| db_inserted_by | True |
| notes | True |

### Lakebase platform default privileges (source of reader SELECT on new objects)
| grantor | schema | default_acl |
| --- | --- | --- |
| cloud_admin | public | {databricks_superuser=r*w*U*/cloud_admin} |
| cloud_admin | public | {databricks_superuser=a*r*w*d*D*m*/cloud_admin} |
PASS: all deny tests
```

## Cell 11: B.3 TXN-0234209 in fraud_dash.case_summary (finished)

```python
cols, rows = uc_rows(f"SELECT case_id, txn_id, customer_id, status, assigned_queue, recommended_action, risk_score, amount, action_count, created_at FROM {UC}.fraud_dash.case_summary WHERE txn_id = '{TRACED_TXN}'")
show(cols, rows, f"B.3 {TRACED_TXN} through UC fraud_dash.case_summary")
assert rows and rows[0][0].startswith("2319d4b7") and rows[0][4] == "auto_block"
print(f"PASS: {TRACED_TXN} -> case {rows[0][0]}, queue {rows[0][4]}")
```

Output:

```text

### B.3 TXN-0234209 through UC fraud_dash.case_summary
| case_id | txn_id | customer_id | status | assigned_queue | recommended_action | risk_score | amount | action_count | created_at |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2319d4b7-bea3-412b-ba6b-8325e1a7a71d | TXN-0234209 | CUST-08669 | open | auto_block | block | 0.9844108757126732 | 323.96 | 1 | 2026-10-21 00:02:21.031588 |
PASS: TXN-0234209 -> case 2319d4b7-bea3-412b-ba6b-8325e1a7a71d, queue auto_block
```

## Cell 12: B.4 Latency of each dashboard dataset query through UC (20 runs) (finished)

```python
def pct(xs, p):
    xs = sorted(xs); k = (len(xs) - 1) * p / 100; f = int(k); c = min(f + 1, len(xs) - 1)
    return xs[f] + (xs[c] - xs[f]) * (k - f)

RUNS = 20
LAT = []
print(f"[{now()}] latency start")
for name in DATASETS:
    sql, _, args = dataset_call(name)
    spark.sql(sql, args=args).collect() if args else spark.sql(sql).collect()   # warm-up, not counted
    ts = []
    for _ in range(RUNS):
        t0 = time.time()
        n = len(spark.sql(sql, args=args).collect() if args else spark.sql(sql).collect())
        ts.append((time.time() - t0) * 1000)
    LAT.append([name, DATASETS[name]["display"], n, f"{pct(ts, 50):.0f}", f"{pct(ts, 95):.0f}", f"{min(ts):.0f}", f"{max(ts):.0f}"])
    print(f"  {name}: p50 {pct(ts, 50):.0f} ms")
print(f"[{now()}] latency end")
show(["dataset", "source", "rows", "p50 ms", "p95 ms", "min ms", "max ms"], LAT, f"B.4 dataset latency through UC on serverless ({RUNS} runs each, after 1 warm-up)", max_w=70)
```

Output:

```text
[2026-10-23 02:25:54.917 UTC] latency start
  ds_kpi_cases: p50 2126 ms
  ds_model_vs_baseline: p50 4801 ms
  ds_score_dist: p50 6869 ms
  ds_cases_daily: p50 4195 ms
  ds_actions_daily: p50 3074 ms
  ds_triage: p50 4851 ms
  ds_triage_options: p50 6058 ms
  ds_recent_cases: p50 2984 ms
  ds_calibration: p50 3101 ms
  ds_exposure: p50 6483 ms
[2026-10-23 02:41:52.196 UTC] latency end

### B.4 dataset latency through UC on serverless (20 runs each, after 1 warm-up)
| dataset | source | rows | p50 ms | p95 ms | min ms | max ms |
| --- | --- | --- | --- | --- | --- | --- |
| ds_kpi_cases | Case KPIs (fraud_dash.case_summary) | 1 | 2126 | 5075 | 1041 | 5086 |
| ds_model_vs_baseline | Model vs baseline rule (fraud_dash.baseline_comparison) | 1 | 4801 | 8726 | 3688 | 8756 |
| ds_score_dist | Risk score distribution (fraud_dash.score_distribution) | 31 | 6869 | 8153 | 3913 | 9828 |
| ds_cases_daily | Cases created per day by queue (fraud_dash.case_summary) | 5 | 4195 | 6324 | 1237 | 7170 |
| ds_actions_daily | Case actions per day (fraud_dash.case_actions_daily) | 7 | 3074 | 5077 | 1121 | 5087 |
| ds_triage | Triage queue top 50 (fraud_dash.triage_queue) | 50 | 4851 | 5815 | 2759 | 5840 |
| ds_triage_options | Triage filter options (fraud_dash.triage_queue) | 4 | 6058 | 8156 | 4893 | 8370 |
| ds_recent_cases | Recent cases (fraud_dash.case_summary) | 50 | 2984 | 4161 | 948 | 5941 |
| ds_calibration | Calibration (fraud_gov.risk_score_calibration) | 12 | 3101 | 4244 | 1050 | 6106 |
| ds_exposure | Exposure (fraud_dash.exposure) | 6 | 6483 | 7845 | 5034 | 8453 |
```

## Cell 13: D.1 Every dashboard dataset through the warehouse (text version of the dashboard) (finished)

```python
print(f"[{now()}] Part D.1 on warehouse {WAREHOUSE_ID}")
md = [f"# Dashboard dataset results ({LOG_DATE})", "",
      f"Dashboard: FE Bar Fraud Ops: Triage & Action (`{DASH_ID}`). Warehouse `{WAREHOUSE_ID}`, Statement Execution API.",
      "SQL is read from the dashboard definition (`serialized_dashboard`). ds_triage runs with its default parameters "
      "(MULTI filters empty, txn_id_f = 'ALL'); only the parameter markers are bound. Generated by validation_notebooks/dashboard_validation.ipynb.", ""]
D1 = {}
for name, d in DATASETS.items():
    sql, params, _ = dataset_call(name)
    cols, rows, ms, sid = wh(sql, params)
    D1[name] = (cols, rows)
    title = f"{name}: {d['display']} ({len(rows)} rows, {ms:.0f} ms, statement {sid})"
    show(cols, rows, title, max_w=70)
    md += [f"## {title}", "", "```sql", d["sql"], "```", "", fmt_table(cols, rows, max_w=120), ""]
md.insert(5, f"Run at {now()}.\n")
out_path = os.path.join(REPO, "logs", f"dashboard_dataset_results_{LOG_DATE}.md")
with open(out_path, "w") as f:
    f.write("\n".join(md) + "\n")
print(f"\nwrote {out_path} ({sum(len(x) for x in md)} chars)")
```

Output:

```text
[2026-10-23 02:41:52.291 UTC] Part D.1 on warehouse 9bbc027402111984

### ds_kpi_cases: Case KPIs (fraud_dash.case_summary) (1 rows, 2505 ms, statement 01f1ce8b-4dbb-11cf-8e6a-8c9cbbd42d3f)
| cases_created_today | open_cases | analyst_review_backlog | visible_cases | as_of_date_utc |
| --- | --- | --- | --- | --- |
| 1 | 7 | 0 | 165 | 2026-10-23 |

### ds_model_vs_baseline: Model vs baseline rule (fraud_dash.baseline_comparison) (1 rows, 2889 ms, statement 01f1ce8b-4f22-1bfb-87e3-e1f5f7deee90)
| model_fraud_amount_caught | baseline_fraud_amount_caught | model_false_positives | baseline_false_positives | model_flagged | baseline_flagged | baseline_rule_text | total_fraud_amount |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 7010482.03 | 933889.13 | 17630 | 30956 | 24201 | 33723 | is_cross_border = 1 AND is_new_device = 1 | 7986207.92 |

### ds_score_dist: Risk score distribution (fraud_dash.score_distribution) (31 rows, 4366 ms, statement 01f1ce8b-50dc-14f3-aef0-8cdb54d79704)
| bucket_lower | bucket_upper | bucket_label | band | recommended_action | txn_count | review_threshold | block_threshold | model_run_id |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0.0 | 0.05 | 0.000 | coarse | approve | 4993 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |
| 0.05 | 0.1 | 0.050 | coarse | approve | 16765 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |
| 0.1 | 0.15 | 0.100 | coarse | approve | 132227 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |
| 0.15 | 0.2 | 0.150 | coarse | approve | 175284 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |
| 0.2 | 0.25 | 0.200 | coarse | approve | 66631 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |
| 0.25 | 0.3 | 0.250 | coarse | approve | 18298 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |
| 0.3 | 0.35 | 0.300 | coarse | approve | 4802 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |
| 0.35 | 0.4 | 0.350 | coarse | approve | 1854 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |
| 0.4 | 0.45 | 0.400 | coarse | approve | 1211 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |
| 0.45 | 0.5 | 0.450 | coarse | approve | 846 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |
| 0.5 | 0.55 | 0.500 | coarse | approve | 877 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |
| 0.55 | 0.6 | 0.550 | coarse | approve | 1432 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |
| 0.6 | 0.65 | 0.600 | coarse | approve | 2096 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |
| 0.65 | 0.7 | 0.650 | coarse | approve | 1688 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |
| 0.7 | 0.75 | 0.700 | coarse | approve | 1707 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |
| 0.75 | 0.8 | 0.750 | coarse | approve | 599 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |
| 0.8 | 0.85 | 0.800 | coarse | approve | 2825 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |
| 0.85 | 0.8714 | 0.850 | coarse | approve | 5545 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |
| 0.8714 | 0.8814 | 0.871 | review threshold 0.8714 | fine_review | review | 3824 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |
| 0.8814 | 0.8914 | 0.881 | fine_review | review | 3036 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |
| 0.8914 | 0.9014 | 0.891 | fine_review | review | 1735 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |
| 0.9014 | 0.9114 | 0.901 | fine_review | review | 1269 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |
| 0.9114 | 0.9214 | 0.911 | fine_review | review | 1693 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |
| 0.9214 | 0.9314 | 0.921 | fine_review | review | 2539 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |
| 0.9314 | 0.9414 | 0.931 | fine_review | review | 4777 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |
| 0.9414 | 0.9503 | 0.941 | fine_review | review | 3314 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |
| 0.9503 | 0.9603 | 0.950 | block threshold 0.9503 | fine_block | block | 917 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |
| 0.9603 | 0.9703 | 0.960 | fine_block | block | 158 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |
| 0.9703 | 0.9803 | 0.970 | fine_block | block | 36 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |
| 0.9803 | 0.9903 | 0.980 | fine_block | block | 856 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |
| 0.9903 | 1.0 | 0.990 | fine_block | block | 47 | 0.8714158290727556 | 0.9502674433961342 | d89beaca8f81447780da60ed2ea7c811 |

### ds_cases_daily: Cases created per day by queue (fraud_dash.case_summary) (5 rows, 2277 ms, statement 01f1ce8b-5376-1b7e-a869-07256d8391d4)
| created_date | assigned_queue | cases_created |
| --- | --- | --- |
| 2026-10-17 | analyst_review | 100 |
| 2026-10-20 | analyst_review | 1 |
| 2026-10-21 | analyst_review | 56 |
| 2026-10-21 | auto_block | 7 |
| 2026-10-23 | auto_block | 1 |

### ds_actions_daily: Case actions per day (fraud_dash.case_actions_daily) (7 rows, 2360 ms, statement 01f1ce8b-54d2-1345-82ec-062f8362fc4a)
| action_date | action_type | action_count | case_count |
| --- | --- | --- | --- |
| 2026-10-17 | case_closed | 100 | 100 |
| 2026-10-17 | case_opened | 100 | 100 |
| 2026-10-20 | case_closed | 1 | 1 |
| 2026-10-20 | case_opened | 1 | 1 |
| 2026-10-21 | case_closed | 57 | 57 |
| 2026-10-21 | case_opened | 63 | 63 |
| 2026-10-23 | case_opened | 1 | 1 |

### ds_triage: Triage queue top 50 (fraud_dash.triage_queue) (50 rows, 2013 ms, statement 01f1ce8b-563a-1d36-bcf0-bdc0854040bd)
| txn_id | customer_id | amount | risk_score | recommended_action | top_shap_signals | case_status | assigned_queue | case_id | risk_rank | filtered_rank |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TXN-0147293 | CUST-07061 | 49.59 | 0.9937617359197244 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.189}, {"featu... | open | auto_block | 82b12d25-bf88-47cb-b0a4-f5a5b62f349d | 1 | 1 |
| TXN-0288343 | CUST-05783 | 31.09 | 0.9928814932431312 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.1856}, {"feat... | open | auto_block | 863334d8-909e-4348-8be4-772d0c7f6e72 | 2 | 2 |
| TXN-0221786 | CUST-00057 | 67.05 | 0.9928754746489601 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.165}, {"featu... | open | auto_block | c37587c0-5091-4fd7-a656-c9df9417d0e3 | 3 | 3 |
| TXN-0417769 | CUST-01726 | 367.85 | 0.9926982635124738 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.0009}, {"feat... | open | auto_block | 98edced4-9dc7-47a3-bbf3-1694bb7b1b43 | 4 | 4 |
| TXN-0432087 | CUST-03840 | 114.02 | 0.9926569090653831 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 1.8947}, {"feat... | open | auto_block | 98adcae4-cec6-46a1-a2c5-1ecd84c299ad | 5 | 5 |
| TXN-0350980 | CUST-01654 | 151.27 | 0.9926219806163414 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 1.9912}, {"feat... | open | auto_block | 030dc7fb-3284-4cc2-9264-06b7de57c2cb | 6 | 6 |
| TXN-0197951 | CUST-04108 | 113.99 | 0.9925588025120645 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 1.9989}, {"feat... | no case | no case | NULL | 7 | 7 |
| TXN-0112255 | CUST-09364 | 169.69 | 0.9924971554250681 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 1.9395}, {"feat... | no case | no case | NULL | 8 | 8 |
| TXN-0045116 | CUST-05980 | 174.26 | 0.9922636509073026 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.1576}, {"feat... | no case | no case | NULL | 9 | 9 |
| TXN-0061730 | CUST-09391 | 86.29 | 0.9922248710537352 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.0339}, {"feat... | no case | no case | NULL | 10 | 10 |
| TXN-0099386 | CUST-02068 | 58.66 | 0.9922040279036098 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.1763}, {"feat... | no case | no case | NULL | 11 | 11 |
| TXN-0259400 | CUST-00057 | 392.9 | 0.992192313929115 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 1.9673}, {"feat... | no case | no case | NULL | 12 | 12 |
| TXN-0330784 | CUST-02280 | 48.69 | 0.9921762302334374 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 1.8898}, {"feat... | no case | no case | NULL | 13 | 13 |
| TXN-0273489 | CUST-01179 | 11.74 | 0.9921410364311569 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.4402}, {"feat... | no case | no case | NULL | 14 | 14 |
| TXN-0091464 | CUST-09856 | 168.61 | 0.9919633367307845 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 1.9514}, {"feat... | no case | no case | NULL | 15 | 15 |
| TXN-0339951 | CUST-09455 | 111.96 | 0.9918889914894486 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.0332}, {"feat... | no case | no case | NULL | 16 | 16 |
| TXN-0426608 | CUST-05132 | 677.81 | 0.9918663339534273 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.18}, {"featur... | no case | no case | NULL | 17 | 17 |
| TXN-0077498 | CUST-00348 | 349.2 | 0.9918024530051684 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 1.9205}, {"feat... | no case | no case | NULL | 18 | 18 |
| TXN-0196520 | CUST-07991 | 215.47 | 0.9917349106298934 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.2116}, {"feat... | no case | no case | NULL | 19 | 19 |
| TXN-0045719 | CUST-05562 | 11.6 | 0.9917174138680963 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.4316}, {"feat... | no case | no case | NULL | 20 | 20 |
| TXN-0254138 | CUST-00134 | 8.84 | 0.9916354438755228 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.1471}, {"feat... | no case | no case | NULL | 21 | 21 |
| TXN-0362832 | CUST-06166 | 94.61 | 0.9915672499280871 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.0305}, {"feat... | no case | no case | NULL | 22 | 22 |
| TXN-0468363 | CUST-09236 | 25.3 | 0.9914498599143503 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.1126}, {"feat... | no case | no case | NULL | 23 | 23 |
| TXN-0399479 | CUST-06166 | 12.46 | 0.9914423994197534 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.2518}, {"feat... | no case | no case | NULL | 24 | 24 |
| TXN-0357211 | CUST-03831 | 353.62 | 0.9914360441793473 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.0304}, {"feat... | no case | no case | NULL | 25 | 25 |
| TXN-0411128 | CUST-06570 | 293.91 | 0.9913287932694228 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 1.9756}, {"feat... | no case | no case | NULL | 26 | 26 |
| TXN-0430313 | CUST-00426 | 33.53 | 0.9913212038548261 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.2021}, {"feat... | no case | no case | NULL | 27 | 27 |
| TXN-0340464 | CUST-01965 | 77.7 | 0.9913210237757103 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 1.9093}, {"feat... | no case | no case | NULL | 28 | 28 |
| TXN-0007113 | CUST-06439 | 15.14 | 0.9913039913503803 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.382}, {"featu... | no case | no case | NULL | 29 | 29 |
| TXN-0392986 | CUST-06478 | 83.15 | 0.9912030763587292 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 1.924}, {"featu... | no case | no case | NULL | 30 | 30 |
| TXN-0415958 | CUST-06075 | 91.06 | 0.9911000430641072 | block | [{"feature": "geo_distance_from_home", "value": 450.27, "shap": 1.7... | no case | no case | NULL | 31 | 31 |
| TXN-0446003 | CUST-01090 | 81.96 | 0.9910853430511175 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.0147}, {"feat... | no case | no case | NULL | 32 | 32 |
| TXN-0370610 | CUST-01486 | 381.31 | 0.9909766715786912 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.2071}, {"feat... | no case | no case | NULL | 33 | 33 |
| TXN-0080888 | CUST-07961 | 11.64 | 0.9909700811838172 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.4677}, {"feat... | no case | no case | NULL | 34 | 34 |
| TXN-0086046 | CUST-08386 | 73.42 | 0.9909430415945573 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.1846}, {"feat... | no case | no case | NULL | 35 | 35 |
| TXN-0497973 | CUST-07128 | 19.75 | 0.9908154840775413 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.2366}, {"feat... | no case | no case | NULL | 36 | 36 |
| TXN-0363094 | CUST-01288 | 18.22 | 0.9907298320519473 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.2613}, {"feat... | no case | no case | NULL | 37 | 37 |
| TXN-0259318 | CUST-05857 | 52.72 | 0.9906944000080727 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.2554}, {"feat... | no case | no case | NULL | 38 | 38 |
| TXN-0269837 | CUST-01844 | 394.09 | 0.9905864198285836 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.5091}, {"feat... | no case | no case | NULL | 39 | 39 |
| TXN-0034898 | CUST-03270 | 22.52 | 0.9904708008044747 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.209}, {"featu... | no case | no case | NULL | 40 | 40 |
| TXN-0024142 | CUST-05958 | 228.16 | 0.9904454917841107 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.2483}, {"feat... | no case | no case | NULL | 41 | 41 |
| TXN-0307939 | CUST-00286 | 41.82 | 0.9904434161865499 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.3078}, {"feat... | no case | no case | NULL | 42 | 42 |
| TXN-0353270 | CUST-05454 | 22.31 | 0.990412701123917 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.1893}, {"feat... | no case | no case | NULL | 43 | 43 |
| TXN-0121093 | CUST-03498 | 274.96 | 0.9903806014885661 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.1662}, {"feat... | no case | no case | NULL | 44 | 44 |
| TXN-0353616 | CUST-04740 | 9.07 | 0.9903465399948289 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.4601}, {"feat... | no case | no case | NULL | 45 | 45 |
| TXN-0326257 | CUST-02201 | 124.34 | 0.9902944266772306 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.3996}, {"feat... | no case | no case | NULL | 46 | 46 |
| TXN-0484780 | CUST-03186 | 74.5 | 0.9902845948055609 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.6202}, {"feat... | no case | no case | NULL | 47 | 47 |
| TXN-0073159 | CUST-05137 | 17.33 | 0.9902287600527504 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.4422}, {"feat... | no case | no case | NULL | 48 | 48 |
| TXN-0401765 | CUST-04377 | 93.35 | 0.9902208124087485 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.6451}, {"feat... | no case | no case | NULL | 49 | 49 |
| TXN-0158754 | CUST-02328 | 27.7 | 0.9902163029289972 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.5551}, {"feat... | no case | no case | NULL | 50 | 50 |

### ds_triage_options: Triage filter options (fraud_dash.triage_queue) (4 rows, 4154 ms, statement 01f1ce8b-576b-11ee-b5ae-1e40cdf8d0e9)
| recommended_action | assigned_queue | case_status | txn_count |
| --- | --- | --- | --- |
| block | auto_block | open | 7 |
| block | no case | no case | 2007 |
| review | analyst_review | closed | 6 |
| review | no case | no case | 22181 |

### ds_recent_cases: Recent cases (fraud_dash.case_summary) (50 rows, 1079 ms, statement 01f1ce8b-59e9-16a8-bbcb-66d85f490e77)
| case_id | txn_id | customer_id | status | assigned_queue | recommended_action | risk_score | amount | action_count | created_at | updated_at | last_action_at |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 030dc7fb-3284-4cc2-9264-06b7de57c2cb | TXN-0350980 | CUST-01654 | open | auto_block | block | 0.9926219806163414 | 151.27 | 1 | 2026-10-23T01:45:33.754Z | 2026-10-23T01:45:33.754Z | 2026-10-23T01:45:33.754Z |
| 6771ac54-d3cc-420e-ad8f-78af025d2ef9 | TXN-0001817 | CUST-04930 | closed | analyst_review | review | 0.20259375439572483 | 223.51 | 2 | 2026-10-21T15:52:43.264Z | 2026-10-21T15:52:43.282Z | 2026-10-21T15:52:43.282Z |
| 4952ac14-9c74-4b34-be29-51c885fa793a | TXN-0490711 | CUST-04397 | closed | analyst_review | review | 0.21657458305487443 | 71.09 | 2 | 2026-10-21T15:52:43.224Z | 2026-10-21T15:52:43.243Z | 2026-10-21T15:52:43.243Z |
| 4d29ea0e-571b-424a-9756-0d9bb922c08c | TXN-0317332 | CUST-03808 | closed | analyst_review | review | 0.14875629222284997 | 52.68 | 2 | 2026-10-21T15:52:43.181Z | 2026-10-21T15:52:43.202Z | 2026-10-21T15:52:43.202Z |
| ad123003-b693-449f-97bd-65786e829a69 | TXN-0066423 | CUST-04163 | closed | analyst_review | review | 0.11632920379290018 | 17.43 | 2 | 2026-10-21T15:52:43.142Z | 2026-10-21T15:52:43.161Z | 2026-10-21T15:52:43.161Z |
| b54ff903-baf1-46f8-b7b1-be5124e2d50b | TXN-0238260 | CUST-04288 | closed | analyst_review | review | 0.17735361892499749 | 33.45 | 2 | 2026-10-21T15:52:43.103Z | 2026-10-21T15:52:43.122Z | 2026-10-21T15:52:43.122Z |
| 5f82573b-2f83-4009-b08b-7b4636da94b1 | TXN-0407261 | CUST-05758 | closed | analyst_review | review | 0.23336738079688715 | 11.99 | 2 | 2026-10-21T15:52:43.065Z | 2026-10-21T15:52:43.084Z | 2026-10-21T15:52:43.084Z |
| c43a9e96-fdb1-4f72-850b-e3c4c7c807d0 | TXN-0259099 | CUST-05209 | closed | analyst_review | review | 0.26598997602211305 | 535.57 | 2 | 2026-10-21T15:52:43.023Z | 2026-10-21T15:52:43.045Z | 2026-10-21T15:52:43.045Z |
| 053207e1-506b-4ce2-84e2-881bf4d89059 | TXN-0284512 | CUST-08551 | closed | analyst_review | review | 0.2190415283372691 | 140.53 | 2 | 2026-10-21T15:52:42.983Z | 2026-10-21T15:52:43.002Z | 2026-10-21T15:52:43.002Z |
| 57813f13-3f44-445a-a8d8-94a91aa61f70 | TXN-0214392 | CUST-09916 | closed | analyst_review | review | 0.14439897954037234 | 73.87 | 2 | 2026-10-21T15:52:42.939Z | 2026-10-21T15:52:42.960Z | 2026-10-21T15:52:42.960Z |
| 97aea7e8-6057-4131-af65-bfd2c3341867 | TXN-0470236 | CUST-01708 | closed | analyst_review | review | 0.2672909192901863 | 398.46 | 2 | 2026-10-21T15:52:42.898Z | 2026-10-21T15:52:42.915Z | 2026-10-21T15:52:42.915Z |
| f120ea93-d566-4235-bda7-e05c3d148e35 | TXN-0444072 | CUST-06757 | closed | analyst_review | review | 0.12275983646254263 | 111.52 | 2 | 2026-10-21T15:52:42.858Z | 2026-10-21T15:52:42.876Z | 2026-10-21T15:52:42.876Z |
| 110c4160-21b5-4545-959e-690fdf413d7a | TXN-0179780 | CUST-09134 | closed | analyst_review | review | 0.23016823523221228 | 19.55 | 2 | 2026-10-21T15:52:42.815Z | 2026-10-21T15:52:42.834Z | 2026-10-21T15:52:42.834Z |
| 093c0452-1071-44fb-b7ad-b2853b06e5ac | TXN-0208546 | CUST-06739 | closed | analyst_review | review | 0.14758809244582247 | 76.32 | 2 | 2026-10-21T15:52:42.773Z | 2026-10-21T15:52:42.793Z | 2026-10-21T15:52:42.793Z |
| 4a748049-2958-4eee-8e6b-eb4f962c2c34 | TXN-0177512 | CUST-03429 | closed | analyst_review | review | 0.13343148539191982 | 39.81 | 2 | 2026-10-21T15:52:42.727Z | 2026-10-21T15:52:42.747Z | 2026-10-21T15:52:42.747Z |
| dea2f40f-f4ca-4802-a561-083deb9ae01c | TXN-0169092 | CUST-01339 | closed | analyst_review | review | 0.23244705906864083 | 134.15 | 2 | 2026-10-21T15:52:42.683Z | 2026-10-21T15:52:42.703Z | 2026-10-21T15:52:42.703Z |
| 400d8d56-de52-4776-b14c-5f7b8f021c12 | TXN-0107363 | CUST-01117 | closed | analyst_review | review | 0.2593570989582907 | 141.49 | 2 | 2026-10-21T15:52:42.639Z | 2026-10-21T15:52:42.661Z | 2026-10-21T15:52:42.661Z |
| 0772be2a-cdaa-4a2c-9af6-dfaaa6c1d980 | TXN-0316789 | CUST-00780 | closed | analyst_review | review | 0.19892723701363563 | 32.14 | 2 | 2026-10-21T15:52:42.594Z | 2026-10-21T15:52:42.617Z | 2026-10-21T15:52:42.617Z |
| 1376bbc2-d350-4244-8e57-268bb0271516 | TXN-0002502 | CUST-05605 | closed | analyst_review | review | 0.13229948787649637 | 1129.86 | 2 | 2026-10-21T15:52:42.547Z | 2026-10-21T15:52:42.572Z | 2026-10-21T15:52:42.572Z |
| 35174062-08f7-48b6-8c6b-1d548a647b9a | TXN-0133348 | CUST-05193 | closed | analyst_review | review | 0.17274196446867718 | 15.5 | 2 | 2026-10-21T15:52:42.497Z | 2026-10-21T15:52:42.522Z | 2026-10-21T15:52:42.522Z |
| 2efd2056-6b26-4d48-a849-c9894e6b3218 | TXN-0212232 | CUST-08933 | closed | analyst_review | review | 0.17220238638935828 | 150.51 | 2 | 2026-10-21T15:52:42.455Z | 2026-10-21T15:52:42.476Z | 2026-10-21T15:52:42.476Z |
| f684538e-331c-4c3b-abe7-4afe9104474e | TXN-0211214 | CUST-00894 | closed | analyst_review | review | 0.10011996604356241 | 12.72 | 2 | 2026-10-21T15:52:42.409Z | 2026-10-21T15:52:42.428Z | 2026-10-21T15:52:42.428Z |
| 61d85620-c7c8-45b5-90fa-ed8225dded55 | TXN-0373944 | CUST-00459 | closed | analyst_review | review | 0.1924290164110434 | 347.17 | 2 | 2026-10-21T15:52:42.367Z | 2026-10-21T15:52:42.387Z | 2026-10-21T15:52:42.387Z |
| eb60c06b-82ca-499a-a3a5-01c9347d4eea | TXN-0245395 | CUST-00215 | closed | analyst_review | review | 0.12154756962213263 | 20.99 | 2 | 2026-10-21T15:52:42.323Z | 2026-10-21T15:52:42.342Z | 2026-10-21T15:52:42.342Z |
| 8703c4d7-4cf6-4bff-bea1-dc23cf2cc07c | TXN-0333222 | CUST-04445 | closed | analyst_review | review | 0.1418796506891301 | 33.82 | 2 | 2026-10-21T15:52:42.276Z | 2026-10-21T15:52:42.297Z | 2026-10-21T15:52:42.297Z |
| e5bd5143-b948-41d6-8033-75ecc92c3240 | TXN-0148358 | CUST-01186 | closed | analyst_review | review | 0.13378663630555443 | 15.55 | 2 | 2026-10-21T15:52:42.232Z | 2026-10-21T15:52:42.254Z | 2026-10-21T15:52:42.254Z |
| 2a50694c-8412-4049-b3c8-956451152604 | TXN-0298528 | CUST-05070 | closed | analyst_review | review | 0.12518646412248832 | 22.3 | 2 | 2026-10-21T15:52:42.188Z | 2026-10-21T15:52:42.209Z | 2026-10-21T15:52:42.209Z |
| 4d766c25-f90a-4c59-a5a6-31822401b1d1 | TXN-0179809 | CUST-06958 | closed | analyst_review | review | 0.1425940396045488 | 85.67 | 2 | 2026-10-21T15:52:42.143Z | 2026-10-21T15:52:42.166Z | 2026-10-21T15:52:42.166Z |
| d07d1942-16d6-4389-8fef-806e6cb91a84 | TXN-0481884 | CUST-08479 | closed | analyst_review | review | 0.1859471997807011 | 138.48 | 2 | 2026-10-21T15:52:42.100Z | 2026-10-21T15:52:42.120Z | 2026-10-21T15:52:42.120Z |
| b9791fd5-61f7-4c79-b129-ce6dab030da0 | TXN-0114409 | CUST-02562 | closed | analyst_review | review | 0.1783079834778691 | 102.64 | 2 | 2026-10-21T15:52:42.057Z | 2026-10-21T15:52:42.077Z | 2026-10-21T15:52:42.077Z |
| b3f2f774-636e-4db8-a819-b2b1e4fe0513 | TXN-0182744 | CUST-03418 | closed | analyst_review | review | 0.17983333243722635 | 233.59 | 2 | 2026-10-21T15:52:42.010Z | 2026-10-21T15:52:42.032Z | 2026-10-21T15:52:42.032Z |
| effab105-d70b-4f14-b6c1-329bcea6c557 | TXN-0364965 | CUST-04877 | closed | analyst_review | review | 0.21366173439332198 | 34.31 | 2 | 2026-10-21T15:52:41.961Z | 2026-10-21T15:52:41.983Z | 2026-10-21T15:52:41.983Z |
| cea71aaa-cd08-4302-bb6b-df3f2ade0233 | TXN-0245350 | CUST-08401 | closed | analyst_review | review | 0.12530164277286368 | 93.17 | 2 | 2026-10-21T15:52:41.914Z | 2026-10-21T15:52:41.935Z | 2026-10-21T15:52:41.935Z |
| 8c47b953-449e-4932-a985-ba9c2163b227 | TXN-0252796 | CUST-07733 | closed | analyst_review | review | 0.20788939174373625 | 101.43 | 2 | 2026-10-21T15:52:41.867Z | 2026-10-21T15:52:41.892Z | 2026-10-21T15:52:41.892Z |
| d16f6672-7cce-4408-a5f7-f05902fd26f1 | TXN-0440664 | CUST-00151 | closed | analyst_review | review | 0.1447198806576098 | 140.55 | 2 | 2026-10-21T15:52:41.820Z | 2026-10-21T15:52:41.843Z | 2026-10-21T15:52:41.843Z |
| 705de7fa-a6aa-4398-8cfe-2e4d81c04bfb | TXN-0009429 | CUST-03655 | closed | analyst_review | review | 0.859720189165183 | 82.15 | 2 | 2026-10-21T15:52:41.772Z | 2026-10-21T15:52:41.799Z | 2026-10-21T15:52:41.799Z |
| 712153c5-d3fd-4554-b946-9ef76b2fd9a5 | TXN-0235053 | CUST-00480 | closed | analyst_review | review | 0.18726476195251227 | 28.76 | 2 | 2026-10-21T15:52:41.722Z | 2026-10-21T15:52:41.749Z | 2026-10-21T15:52:41.749Z |
| a4325958-f349-4fc3-835b-0ab9b28fed5a | TXN-0006957 | CUST-08949 | closed | analyst_review | review | 0.1623851017414149 | 73.33 | 2 | 2026-10-21T15:52:41.677Z | 2026-10-21T15:52:41.700Z | 2026-10-21T15:52:41.700Z |
| d39948cd-06bb-4a71-a587-00f64f6a7c08 | TXN-0224754 | CUST-03366 | closed | analyst_review | review | 0.1219560810396327 | 59.67 | 2 | 2026-10-21T15:52:41.634Z | 2026-10-21T15:52:41.654Z | 2026-10-21T15:52:41.654Z |
| c40625a0-a229-4221-b279-ed2465839afc | TXN-0289304 | CUST-01864 | closed | analyst_review | review | 0.09188491559910018 | 52.73 | 2 | 2026-10-21T15:52:41.590Z | 2026-10-21T15:52:41.611Z | 2026-10-21T15:52:41.611Z |
| 34e459d4-868c-4b43-a3d4-b99f93fcf3c8 | TXN-0208014 | CUST-03871 | closed | analyst_review | review | 0.2050866587290096 | 53.4 | 2 | 2026-10-21T15:52:41.545Z | 2026-10-21T15:52:41.566Z | 2026-10-21T15:52:41.566Z |
| 6b814004-6493-449a-80c0-34aec1d994b2 | TXN-0052492 | CUST-02398 | closed | analyst_review | review | 0.1465482692120281 | 201.28 | 2 | 2026-10-21T15:52:41.496Z | 2026-10-21T15:52:41.520Z | 2026-10-21T15:52:41.520Z |
| 932dedae-3636-436b-bc18-1591d7310108 | TXN-0215441 | CUST-09205 | closed | analyst_review | review | 0.16645107203902312 | 108.8 | 2 | 2026-10-21T15:52:41.450Z | 2026-10-21T15:52:41.472Z | 2026-10-21T15:52:41.472Z |
| 29fea544-253e-40b5-abb8-7ad67ec3617e | TXN-0310958 | CUST-07362 | closed | analyst_review | review | 0.8899425379921876 | 158.7 | 2 | 2026-10-21T15:52:41.404Z | 2026-10-21T15:52:41.429Z | 2026-10-21T15:52:41.429Z |
| 73ab091c-a976-425a-94f6-408125ec404b | TXN-0411752 | CUST-03740 | closed | analyst_review | review | 0.12557981363693357 | 35.79 | 2 | 2026-10-21T15:52:41.359Z | 2026-10-21T15:52:41.381Z | 2026-10-21T15:52:41.381Z |
| d546fb9a-2e5e-49ee-a368-8286609ab204 | TXN-0334314 | CUST-06583 | closed | analyst_review | review | 0.13145078295698523 | 201.4 | 2 | 2026-10-21T15:52:41.313Z | 2026-10-21T15:52:41.336Z | 2026-10-21T15:52:41.336Z |
| 82104645-5419-4583-b65e-8e480e4ffc75 | TXN-0488125 | CUST-00204 | closed | analyst_review | review | 0.9383960788497928 | 115.62 | 2 | 2026-10-21T15:52:41.261Z | 2026-10-21T15:52:41.292Z | 2026-10-21T15:52:41.292Z |
| 61ed57a2-08cb-455a-b133-b3b24d779452 | TXN-0426172 | CUST-09834 | closed | analyst_review | review | 0.16320251763071206 | 31.14 | 2 | 2026-10-21T15:52:41.205Z | 2026-10-21T15:52:41.228Z | 2026-10-21T15:52:41.228Z |
| 7e2a3d13-58fa-47f6-b6e9-8e8e299edd90 | TXN-0216591 | CUST-06844 | closed | analyst_review | review | 0.09450388444062752 | 194.31 | 2 | 2026-10-21T15:52:41.158Z | 2026-10-21T15:52:41.179Z | 2026-10-21T15:52:41.179Z |
| f597179b-0be8-40f6-a243-31c8f38e44ac | TXN-0464103 | CUST-07002 | closed | analyst_review | review | 0.13953806523916654 | 333.97 | 2 | 2026-10-21T15:52:41.115Z | 2026-10-21T15:52:41.136Z | 2026-10-21T15:52:41.136Z |

### ds_calibration: Calibration (fraud_gov.risk_score_calibration) (12 rows, 2349 ms, statement 01f1ce8b-5a8b-166d-9a09-9f13fe654bc7)
| bucket | bucket_order | lower_bound | upper_bound | row_count | fraud_count | observed_precision | confidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| decile_01 | 1 | 0.0 | 0.12031666279070152 | 9293 | 47 | 0.005057570214139675 | low |
| decile_02 | 2 | 0.12031666279070152 | 0.1363359193755477 | 9293 | 52 | 0.005595609598622619 | low |
| decile_03 | 3 | 0.1363359193755477 | 0.14683075112279784 | 9292 | 43 | 0.004627636676711149 | low |
| decile_04 | 4 | 0.14683075112279784 | 0.15628224286019438 | 9293 | 60 | 0.00645647261379533 | low |
| decile_05 | 5 | 0.15628224286019438 | 0.1665247300604653 | 9292 | 56 | 0.006026689625484288 | low |
| decile_06 | 6 | 0.1665247300604653 | 0.17856409143600466 | 9293 | 45 | 0.004842354460346497 | low |
| decile_07 | 7 | 0.17856409143600466 | 0.19349231962587188 | 9293 | 51 | 0.005488001721726031 | low |
| decile_08 | 8 | 0.19349231962587188 | 0.21589920133538917 | 9292 | 51 | 0.005488592337494619 | low |
| decile_09 | 9 | 0.21589920133538917 | 0.2659892040112607 | 9293 | 49 | 0.005272785967932853 | low |
| decile_10 | 10 | 0.2659892040112607 | 0.8714158290727556 | 5438 | 240 | 0.04413387274733358 | low |
| review_band | 11 | 0.8714158290727556 | 0.9502674433961342 | 3567 | 897 | 0.2514718250630782 | low |
| block_band | 12 | 0.9502674433961342 | 1.0 | 288 | 144 | 0.5 | medium |

### ds_exposure: Exposure (fraud_dash.exposure) (6 rows, 3445 ms, statement 01f1ce8b-5bf7-1851-ae5a-0f9eb6b3eb10)
| recommended_action | fraud_label | txn_count | total_amount | fraud_amount_caught | fraud_amount_missed |
| --- | --- | --- | --- | --- | --- |
| approve | fraud | 3756 | 975725.89 | 0.0 | 975725.89 |
| approve | not fraud | 435924 | 5.993042663E7 | 0.0 | 0.0 |
| block | fraud | 1278 | 524286.8 | 524286.8 | 0.0 |
| block | not fraud | 736 | 589241.33 | 0.0 | 0.0 |
| review | fraud | 5293 | 6486195.23 | 6486195.23 | 0.0 |
| review | not fraud | 16894 | 1.979822868E7 | 0.0 | 0.0 |

wrote /Workspace/Users/alex.owen@databricks.com/FE-BAR-2026-repo/logs/dashboard_dataset_results_2026-10-22.md (35234 chars)
```

## Cell 14: D.2 Live-read proof: agent opens a case, dashboard queries see it with no sync or job (finished)

```python
from fraud_triage_agent import FraudTriageAgent
from mlflow.types.responses import ResponsesAgentRequest
mlflow.set_experiment("/Users/alex.owen@databricks.com/fe_bar_fraud_triage_agent")

KPI_SQL, _, _ = dataset_call("ds_kpi_cases")
T = {}
T["0_start"] = now(); t0_ms = int(time.time() * 1000)

cols, rows, ms, sid_before = wh(KPI_SQL)
T["1_before_query"] = now()
kpi_before = dict(zip(cols, rows[0]))
show(cols, rows, f"BEFORE  ds_kpi_cases  [{T['1_before_query']}]  statement {sid_before}")

cand_sql = (f"SELECT txn_id, customer_id, amount, risk_score, risk_rank, case_status FROM {UC}.fraud_dash.triage_queue "
            "WHERE recommended_action = 'block' AND case_status = 'no case' ORDER BY risk_score DESC, txn_id LIMIT 1")
cols, rows, _, _ = wh(cand_sql)
show(cols, rows, "Candidate: highest-risk block transaction with no case and amount <= 10000 (fraud_dash.triage_queue)")
LIVE_TXN = rows[0][0]
assert float(rows[0][2]) <= 10000
assert not admin.get_cases_for_txn(LIVE_TXN), "candidate already has a case in Postgres"
T["2_candidate"] = now()

# Agent (fraud_triage_agent.ipynb pattern): the LLM decides and calls create_fraud_case,
# which writes through LakebaseCases(pg_role='fraud_triage_agent').
agent = FraudTriageAgent()
t_a = time.time()
resp = agent.predict(ResponsesAgentRequest(input=[{"role": "user", "content": f"Open a case for {LIVE_TXN} and route it."}]))
T["3_agent_done"] = now()
print(f"\nAgent latency {time.time() - t_a:.1f}s, trace {mlflow.get_last_active_trace_id()}")
texts = []
for o in resp.output:
    for c_ in (getattr(o, "content", None) or []):
        if isinstance(c_, dict) and c_.get("text"):
            texts.append(c_["text"])
print("\n".join(texts)[-1500:])
new_cases = admin.get_cases_for_txn(LIVE_TXN)
assert len(new_cases) == 1, new_cases
LIVE_CASE = str(new_cases[0]["case_id"])
print(f"\nPostgres write: case {LIVE_CASE}, created_by={new_cases[0]['created_by']}, db_inserted_by={new_cases[0]['db_inserted_by']}, created_at={new_cases[0]['created_at']}")

# Same dataset SQL again, immediately, no sync or job in between
cols, rows, ms, sid_after = wh(KPI_SQL)
T["4_after_query"] = now()
kpi_after = dict(zip(cols, rows[0]))
show(cols, rows, f"AFTER   ds_kpi_cases  [{T['4_after_query']}]  statement {sid_after}")

cols, rows, _, _ = wh(f"SELECT case_id, txn_id, customer_id, status, assigned_queue, recommended_action, risk_score, amount, action_count, created_at FROM {UC}.fraud_dash.case_summary WHERE txn_id = '{LIVE_TXN}'")
T["5_case_row"] = now()
show(cols, rows, f"New case row from fraud_dash.case_summary via warehouse [{T['5_case_row']}]")
assert rows and rows[0][0] == LIVE_CASE

show(["metric", "before", "after", "delta"],
     [[k, kpi_before[k], kpi_after[k], int(kpi_after[k]) - int(kpi_before[k])] for k in ["cases_created_today", "open_cases", "visible_cases"]],
     "Before vs after (same ds_kpi_cases SQL the dashboard counters run)")

# Nothing ran in between: job runs and pipeline updates since the start of this cell
t1_ms = int(time.time() * 1000)
job_runs = [r for r in w.jobs.list_runs(job_id=JOB_ID, start_time_from=t0_ms, start_time_to=t1_ms)]
upd = [u for u in (w.pipelines.list_updates(pipeline_id=SYNC_PIPELINE, max_results=5).updates or []) if (u.creation_time or 0) >= t0_ms]
last = (w.pipelines.list_updates(pipeline_id=SYNC_PIPELINE, max_results=1).updates or [None])[0]
show(["check", "value"], [[f"job {JOB_ID} runs started in window", len(job_runs)],
                         [f"sync pipeline {SYNC_PIPELINE} updates created in window", len(upd)],
                         ["latest sync pipeline update", f"{last.update_id} {last.state} created {dt.datetime.fromtimestamp(last.creation_time/1000, dt.timezone.utc):%Y-%m-%d %H:%M:%S} UTC" if last else "none"]],
     "No sync or job run between before and after")
assert not job_runs and not upd
show(["step", "timestamp"], sorted(T.items()), "Timestamps")
assert int(kpi_after["cases_created_today"]) == int(kpi_before["cases_created_today"]) + 1
assert int(kpi_after["open_cases"]) == int(kpi_before["open_cases"]) + 1
print(f"\nPASS: live read. case {LIVE_CASE} for {LIVE_TXN} is visible to the dashboard's dataset queries with no sync or job.")
```

Output:

```text
/local_disk0/.ephemeral_nfs/envs/pythonEnv-72cfc387-1b28-4d74-a0ae-04f7494599b3/lib/python3.12/site-packages/langgraph/checkpoint/base/__init__.py:18: LangChainPendingDeprecationWarning: The default value of `allowed_objects` will change in a future version. Pass an explicit value (e.g., allowed_objects='messages' or allowed_objects='core') to suppress this warning.
  from langgraph.checkpoint.serde.jsonplus import JsonPlusSerializer
2026/10/23 02:42:21 WARNING mlflow.utils.autologging_utils: MLflow langchain autologging is known to be compatible with 1.0.0 <= langchain, but the installed version is 0.3.30. If you encounter errors during autologging, try upgrading / downgrading langchain to a compatible version, or try upgrading MLflow.
If you are using MLflow Tracing, you can migrate your traces to Unity Catalog for unlimited storage, fine-grained access controls, and queryability from notebooks, SQL, and dashboards. Learn more: https://docs.databricks.com/aws/en/mlflow3/genai/tracing/migrate-traces-to-uc

### BEFORE  ds_kpi_cases  [2026-10-23 02:42:24.965 UTC]  statement 01f1ce8b-5f4a-149a-a1e5-a923fc811537
| cases_created_today | open_cases | analyst_review_backlog | visible_cases | as_of_date_utc |
| --- | --- | --- | --- | --- |
| 1 | 7 | 0 | 165 | 2026-10-23 |

### Candidate: highest-risk block transaction with no case and amount <= 10000 (fraud_dash.triage_queue)
| txn_id | customer_id | amount | risk_score | risk_rank | case_status |
| --- | --- | --- | --- | --- | --- |
| TXN-0197951 | CUST-04108 | 113.99 | 0.9925588025120645 | 7 | no case |
2026/10/23 02:42:26 WARNING mlflow.tracking.context.registry: Encountered unexpected error during resolving tags: getContext().extraContext() is not a CommandContext accessor, it is not available or is misspelled.
/local_disk0/.ephemeral_nfs/envs/pythonEnv-72cfc387-1b28-4d74-a0ae-04f7494599b3/lib/python3.12/site-packages/pydantic/main.py:464: UserWarning: Pydantic serializer warnings:
  PydanticSerializationUnexpectedValue(Expected `str` - serialized value may not be as expected [field_name='content', input_value=[{'type': 'reasoning', 's...Ya4k/bWJxAlbWgYAQ=='}]}], input_type=list])
  return self.__pydantic_serializer__.to_python(
/local_disk0/.ephemeral_nfs/envs/pythonEnv-72cfc387-1b28-4d74-a0ae-04f7494599b3/lib/python3.12/site-packages/pydantic/main.py:464: UserWarning: Pydantic serializer warnings:
  PydanticSerializationUnexpectedValue(Expected `str` - serialized value may not be as expected [field_name='content', input_value=[{'type': 'reasoning', 's...RTOsvo6gi/NVNo8GAE='}]}], input_type=list])
  return self.__pydantic_serializer__.to_python(
/local_disk0/.ephemeral_nfs/envs/pythonEnv-72cfc387-1b28-4d74-a0ae-04f7494599b3/lib/python3.12/site-packages/pydantic/main.py:464: UserWarning: Pydantic serializer warnings:
  PydanticSerializationUnexpectedValue(Expected `str` - serialized value may not be as expected [field_name='content', input_value=[{'type': 'reasoning', 's...dMCnE5pNiN7OcomGAE='}]}], input_type=list])
  return self.__pydantic_serializer__.to_python(

Agent latency 17.4s, trace tr-6659ce2b852915f489c9add9eef92cbd
e in the case that it was opened without a signal explanation.
- **What I do have:** the risk score is 0.9926 on a $113.99 transaction from 2026-05-02.
- **Why it matters:** that amount is only about twice the customer's 30-day average of $55.50. Without the signals, I can't say what pushed the score so high.

**Recommended action:** Block, as recommended by the model.

**Confidence:** Medium (observed precision 0.50 in block_band, n=288). Historically, only about half of transactions in this band turned out to be fraud.

**Routed queue:** auto_block.

**Customer context (CUST-04108):**
- **Risk profile:** high risk segment, 23 months tenure, home region US-East.
- **Last 30 days:** 10 transactions, 3 different devices, 4 countries and 5 cross-border transactions.
- **Prior outcomes:** 1 prior case, 0 confirmed fraud.
- **Recent scores:** two earlier transactions scored about 0.93 and 0.95 and were sent to review (TXN-0259770 and TXN-0261357, in September). Every other recent transaction was approved with a low score, apart from one at 0.52 that was also approved.

**Suggested next step:**
1. Because precision is only 0.50, have an analyst check this block soon, so a legitimate customer isn't held for long.
2. Re-run the signal explanation once the tool is fixed. It should show whether the device and country activity is driving the score.
3. Look at the two earlier review cases for this customer. The prior case has no confirmed fraud, which may mean they were false positives.

Postgres write: case c2b2ec3a-a1a7-444f-a1c8-969af362c0ee, created_by=fraud_triage_copilot:agent, db_inserted_by=alex.owen@databricks.com, created_at=2026-10-23 02:42:37.630448+00:00

### AFTER   ds_kpi_cases  [2026-10-23 02:42:45.311 UTC]  statement 01f1ce8b-6c8f-19c4-8749-95aeef4890c1
| cases_created_today | open_cases | analyst_review_backlog | visible_cases | as_of_date_utc |
| --- | --- | --- | --- | --- |
| 2 | 8 | 0 | 166 | 2026-10-23 |

### New case row from fraud_dash.case_summary via warehouse [2026-10-23 02:42:47.380 UTC]
| case_id | txn_id | customer_id | status | assigned_queue | recommended_action | risk_score | amount | action_count | created_at |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| c2b2ec3a-a1a7-444f-a1c8-969af362c0ee | TXN-0197951 | CUST-04108 | open | auto_block | block | 0.9925588025120645 | 113.99 | 1 | 2026-10-23T02:42:37.630Z |

### Before vs after (same ds_kpi_cases SQL the dashboard counters run)
| metric | before | after | delta |
| --- | --- | --- | --- |
| cases_created_today | 1 | 2 | 1 |
| open_cases | 7 | 8 | 1 |
| visible_cases | 165 | 166 | 1 |

### No sync or job run between before and after
| check | value |
| --- | --- |
| job 1115396029932218 runs started in window | 0 |
| sync pipeline f8690359-4bb1-45b9-8fdb-5bd892239db2 update... | 0 |
| latest sync pipeline update | af5f4a17-d2b7-4c5c-8367-025f8be5b697 UpdateInfoState.COMP... |

### Timestamps
| step | timestamp |
| --- | --- |
| 0_start | 2026-10-23 02:42:21.900 UTC |
| 1_before_query | 2026-10-23 02:42:24.965 UTC |
| 2_candidate | 2026-10-23 02:42:26.692 UTC |
| 3_agent_done | 2026-10-23 02:42:44.164 UTC |
| 4_after_query | 2026-10-23 02:42:45.311 UTC |
| 5_case_row | 2026-10-23 02:42:47.380 UTC |

PASS: live read. case c2b2ec3a-a1a7-444f-a1c8-969af362c0ee for TXN-0197951 is visible to the dashboard's dataset queries with no sync or job.
Trace(trace_id='tr-6659ce2b852915f489c9add9eef92cbd')
```

## Cell 15: D.3 End-to-end trace for TXN-0234209 (finished)

```python
print(f"[{now()}] D.3 end-to-end trace for {TRACED_TXN}")
cols, rows, _, _ = wh(f"SELECT * FROM {UC}.fraud_gov.txn_risk_current WHERE txn_id = '{TRACED_TXN}'")
show(cols, rows, "fraud_gov.txn_risk_current (warehouse)", max_w=200)
cols, rows, _, _ = wh(f"SELECT * FROM {UC}.fraud_dash.case_summary WHERE txn_id = '{TRACED_TXN}'")
show(cols, rows, "fraud_dash.case_summary (warehouse)")
sql, params, _ = dataset_call("ds_triage", txn_id=TRACED_TXN)
cols, rows, _, _ = wh(sql, params)
show(cols, rows, f"Triage queue dataset ds_triage with txn_id filter = {TRACED_TXN} (warehouse)", max_w=200)
assert len(rows) == 1 and rows[0][0] == TRACED_TXN

# Journey: raw -> silver -> gold -> score -> Lakebase -> agent -> case -> dashboard
CAT = "workshop_guy_catalog.fe_bar_a0"
hops = [
    ("raw/bronze", f"SELECT count(*) FROM {CAT}.fact_transactions_bronze WHERE txn_id = '{TRACED_TXN}'"),
    ("silver", f"SELECT count(*) FROM {CAT}.fact_transactions_silver WHERE txn_id = '{TRACED_TXN}'"),
    ("gold features", f"SELECT count(*) FROM {CAT}.txn_features_gold WHERE txn_id = '{TRACED_TXN}'"),
    ("score (Delta)", f"SELECT concat(round(risk_score, 5), ' ', recommended_action) FROM {CAT}.scored_transactions WHERE txn_id = '{TRACED_TXN}'"),
    ("Lakebase synced", f"SELECT concat(round(risk_score, 5), ' ', recommended_action) FROM {UC}.fraud.txn_risk_current WHERE txn_id = '{TRACED_TXN}'"),
    ("Lakebase governed", f"SELECT concat(round(risk_score, 5), ' ', recommended_action) FROM {UC}.fraud_gov.txn_risk_current WHERE txn_id = '{TRACED_TXN}'"),
    ("dashboard case_summary", f"SELECT concat(case_id, ' ', assigned_queue, ' ', status) FROM {UC}.fraud_dash.case_summary WHERE txn_id = '{TRACED_TXN}'"),
]
journey = []
for hop, q_ in hops:
    try: journey.append([hop, uc_rows(q_)[1][0][0]])
    except Exception as e: journey.append([hop, f"ERR {type(e).__name__}: {str(e).splitlines()[0][:100]}"])
c = admin.get_cases_for_txn(TRACED_TXN)[0]
journey.insert(6, ["agent -> case (Postgres)", f"{c['case_id']} created_by={c['created_by']} db_inserted_by={c['db_inserted_by']}"])
show(["hop", "evidence for " + TRACED_TXN], journey, "Journey raw -> silver -> gold -> score -> Lakebase -> agent -> case -> dashboard", max_w=120)
```

Output:

```text
[2026-10-23 02:42:47.789 UTC] D.3 end-to-end trace for TXN-0234209

### fraud_gov.txn_risk_current (warehouse)
| txn_id | customer_id | risk_score | recommended_action | top_shap_signals | model_version | scored_at |
| --- | --- | --- | --- | --- | --- | --- |
| TXN-0234209 | CUST-08669 | 0.9844108757126732 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.5724}, {"feature": "geo_distance_from_home", "value": 450.63, "shap": 1.8741}, {"feature": "is_online", "value": 1.0, "shap": 1.2001}] | 1 | 2026-10-21T02:36:46.583Z |

### fraud_dash.case_summary (warehouse)
| case_id | txn_id | customer_id | status | assigned_queue | recommended_action | created_at | updated_at | risk_score | amount | action_count | last_action_at |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2319d4b7-bea3-412b-ba6b-8325e1a7a71d | TXN-0234209 | CUST-08669 | open | auto_block | block | 2026-10-21T00:02:21.031Z | 2026-10-21T00:02:21.031Z | 0.9844108757126732 | 323.96 | 1 | 2026-10-21T00:02:21.031Z |

### Triage queue dataset ds_triage with txn_id filter = TXN-0234209 (warehouse)
| txn_id | customer_id | amount | risk_score | recommended_action | top_shap_signals | case_status | assigned_queue | case_id | risk_rank | filtered_rank |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TXN-0234209 | CUST-08669 | 323.96 | 0.9844108757126732 | block | [{"feature": "is_new_device", "value": 1.0, "shap": 2.5724}, {"feature": "geo_distance_from_home", "value": 450.63, "shap": 1.8741}, {"feature": "is_online", "value": 1.0, "shap": 1.2001}] | open | auto_block | 2319d4b7-bea3-412b-ba6b-8325e1a7a71d | 762 | 1 |

### Journey raw -> silver -> gold -> score -> Lakebase -> agent -> case -> dashboard
| hop | evidence for TXN-0234209 |
| --- | --- |
| raw/bronze | 2 |
| silver | 1 |
| gold features | 1 |
| score (Delta) | 0.98441 block |
| Lakebase synced | 0.98441 block |
| Lakebase governed | 0.98441 block |
| agent -> case (Postgres) | 2319d4b7-bea3-412b-ba6b-8325e1a7a71d created_by=fraud_triage_copilot:agent db_inserted_by=alex.owen@databricks.com |
| dashboard case_summary | 2319d4b7-bea3-412b-ba6b-8325e1a7a71d auto_block open |
```

## Cell 16: Summary (finished)

```python
summary = {
    "run_at": now(), "dashboard_id": DASH_ID, "warehouse_id": WAREHOUSE_ID, "uc_reader_role": READER,
    "uc_cases_raw": UC_CASES_BEFORE, "dash_cases": DASH_CASES, "lead_cases_at_B1": LEAD_CASES,
    "thresholds": {"block": BLOCK_T, "review": REVIEW_T, "run": MLFLOW_RUN},
    "deny_tests": {r[0]: r[1] for r in results},
    "latency_ms": {r[0]: {"p50": r[3], "p95": r[4]} for r in LAT},
    "live_proof": {"txn_id": LIVE_TXN, "case_id": LIVE_CASE, "before": kpi_before, "after": kpi_after, "timestamps": T},
}
print(json.dumps(summary, indent=2, default=str))
admin.close(); lead.close()
```

Output:

```text
{
  "run_at": "2026-10-23 02:43:17.907 UTC",
  "dashboard_id": "01f1ce7f835a1e81b05ebb664bf0994c",
  "warehouse_id": "9bbc027402111984",
  "uc_reader_role": "databricks_reader_17063",
  "uc_cases_raw": 0,
  "dash_cases": 165,
  "lead_cases_at_B1": 170,
  "thresholds": {
    "block": 0.9502674433961342,
    "review": 0.8714158290727556,
    "run": "d89beaca8f81447780da60ed2ea7c811"
  },
  "deny_tests": {
    "UC: SELECT count(*) FROM cases.fraud_cases": "PASS",
    "UC: SELECT notes, db_inserted_by FROM cases.fraud_cases": "PASS",
    "UC: SELECT notes, db_inserted_by FROM cases.case_actions": "PASS",
    "UC: SELECT notes FROM fraud_dash.case_summary": "PASS",
    "UC: SELECT created_by FROM fraud_dash.case_summary": "PASS",
    "UC: SELECT db_inserted_by FROM fraud_dash.case_summary": "PASS",
    "UC: INSERT INTO fraud_dash.model_thresholds": "PASS",
    "UC: UPDATE cases.fraud_cases SET notes = notes": "PASS",
    "UC: DELETE FROM fraud_dash.case_summary WHERE false": "PASS"
  },
  "latency_ms": {
    "ds_kpi_cases": {
      "p50": "2126",
      "p95": "5075"
    },
    "ds_model_vs_baseline": {
      "p50": "4801",
      "p95": "8726"
    },
    "ds_score_dist": {
      "p50": "6869",
      "p95": "8153"
    },
    "ds_cases_daily": {
      "p50": "4195",
      "p95": "6324"
    },
    "ds_actions_daily": {
      "p50": "3074",
      "p95": "5077"
    },
    "ds_triage": {
      "p50": "4851",
      "p95": "5815"
    },
    "ds_triage_options": {
      "p50": "6058",
      "p95": "8156"
    },
    "ds_recent_cases": {
      "p50": "2984",
      "p95": "4161"
    },
    "ds_calibration": {
      "p50": "3101",
      "p95": "4244"
    },
    "ds_exposure": {
      "p50": "6483",
      "p95": "7845"
    }
  },
  "live_proof": {
    "txn_id": "TXN-0197951",
    "case_id": "c2b2ec3a-a1a7-444f-a1c8-969af362c0ee",
    "before": {
      "cases_created_today": "1",
      "open_cases": "7",
      "analyst_review_backlog": "0",
      "visible_cases": "165",
      "as_of_date_utc": "2026-10-23"
    },
    "after": {
      "cases_created_today": "2",
      "open_cases": "8",
      "analyst_review_backlog": "0",
      "visible_cases": "166",
      "as_of_date_utc": "2026-10-23"
    },
    "timestamps": {
      "0_start": "2026-10-23 02:42:21.900 UTC",
      "1_before_query": "2026-10-23 02:42:24.965 UTC",
      "2_candidate": "2026-10-23 02:42:26.692 UTC",
      "3_agent_done": "2026-10-23 02:42:44.164 UTC",
      "4_after_query": "2026-10-23 02:42:45.311 UTC",
      "5_case_row": "2026-10-23 02:42:47.380 UTC"
    }
  }
}
```

