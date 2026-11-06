"""
app.py – FE Bar Fraud Triage App (Streamlit) — Step 9

Pages:
  1. Triage Queue   — top 50 block/review from fraud_gov.txn_risk_current (as fraud_triage_agent)
  2. Transaction Detail — Explain + Open Case via FraudTriageAgent (in-process)
  3. Ask Genie      — Genie Conversation API → space 01f1d7b464d510b9aa6cde48300787ca
  4. Dashboard      — link to 01f1ce7f835a1e81b05ebb664bf0994c

Logging: every Explain, Open-case, and Genie query writes one structured JSON line to
stdout (timestamp, page, txn_id/case_id/conv_id, latency_ms, ok/error). No PII, no tokens.

Auth: app service principal via auto-injected DATABRICKS_CLIENT_ID/DATABRICKS_CLIENT_SECRET.
Lakebase: psycopg3 + w.postgres.generate_database_credential, SET ROLE fraud_triage_agent.
Agent runs in-process (not Model Serving) because MLflow’s DatabricksLakebase resource only
accepts provisioned database_instance_name; fe-bar-fraud-analytics is an Autoscaling project.

fraud_triage_agent.py and lakebase_cases.py are byte-identical copies of the repo-root
originals, verified by SHA-256 in validation_notebooks/app_validation.ipynb.
"""

import json
import os
import sys
import time
from datetime import datetime, timezone

import streamlit as st

# ---- Path setup -----------------------------------------------------------
# app/ is the CWD; fraud_triage_agent.py and lakebase_cases.py are co-located.
# fraud_triage_agent.py has sys.path.insert(0, '/Workspace/.../FE-BAR-2026-repo')
# at line 35; that path doesn’t exist on the app compute but the insert is silent
# and harmless — lakebase_cases import resolves from the same directory.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# ---- Resource env vars (from app.yaml valueFrom + static thresholds) ------
GENIE_SPACE_ID   = os.environ.get("GENIE_SPACE_ID",          "01f1d7b464d510b9aa6cde48300787ca")
WAREHOUSE_ID     = os.environ.get("DATABRICKS_WAREHOUSE_ID", "9bbc027402111984")
BLOCK_THRESHOLD  = float(os.environ.get("BLOCK_THRESHOLD",   "0.9502674433961342"))
REVIEW_THRESHOLD = float(os.environ.get("REVIEW_THRESHOLD",  "0.8714158290727556"))
DAGENT_PG_ROLE   = "fraud_triage_agent"
TRIAGE_LIMIT     = 50
DASHBOARD_URL    = (
    "https://fevm-workshop-guy.cloud.databricks.com"
    "/dashboardsv3/01f1ce7f835a1e81b05ebb664bf0994c/published"
)


# ---- Structured logging ---------------------------------------------------
def _log(page: str, event: str, latency_ms: int, ok: bool, **kw) -> None:
    """Write one structured JSON line to stdout. No PII, no tokens."""
    entry = {
        "ts":         datetime.now(timezone.utc).isoformat(),
        "page":       page,
        "event":      event,
        "latency_ms": latency_ms,
        "ok":         ok,
    }
    # Strip any accidentally-passed sensitive keys
    entry.update({k: v for k, v in kw.items() if k not in ("token", "password", "secret")})
    print(json.dumps(entry, default=str), flush=True)


# ---- Cached resources (one per app process) --------------------------------
@st.cache_resource(show_spinner="Connecting to Lakebase…")
def _lc():
    from lakebase_cases import LakebaseCases
    return LakebaseCases(pg_role=DAGENT_PG_ROLE)


@st.cache_resource(show_spinner="Loading fraud triage agent…")
def _agent():
    # Importing triggers mlflow.models.set_model(FraudTriageAgent()) at module level;
    # we create a second instance here which is the one the app actually uses.
    from fraud_triage_agent import FraudTriageAgent
    return FraudTriageAgent()


@st.cache_resource
def _w():
    from databricks.sdk import WorkspaceClient
    return WorkspaceClient()


# ---- Genie Conversation API -----------------------------------------------
def _call_genie(question: str) -> dict:
    """Call Genie Conversation API, poll until COMPLETED, return result dict.

    Returns:
        conv_id, msg_id, status, answer_text, generated_sql, result_rows
    """
    import requests
    from databricks.sdk.core import Config

    cfg = Config()
    # cfg.host already includes the scheme (https://...)
    base = f"{cfg.host.rstrip('/')}/api/2.0/genie/spaces/{GENIE_SPACE_ID}"

    def _h():
        return {**cfg.authenticate(), "Content-Type": "application/json"}

    # 1. Start conversation
    r = requests.post(f"{base}/start-conversation", headers=_h(),
                      json={"content": question}, timeout=30)
    r.raise_for_status()
    data  = r.json()
    conv_id = data.get("conversation_id") or data.get("id", "")
    msg_id  = data.get("message_id", "")

    # 2. Poll until COMPLETED (up to 120 s)
    msg = {}
    for _ in range(120):
        r = requests.get(
            f"{base}/conversations/{conv_id}/messages/{msg_id}",
            headers=_h(), timeout=30,
        )
        r.raise_for_status()
        msg    = r.json()
        status = msg.get("status", "")
        if status in ("COMPLETED", "FAILED", "CANCELLED", "QUERY_RESULT_EXPIRED"):
            break
        time.sleep(1)

    # 3. Extract answer text and SQL
    answer_text  = ""
    generated_sql = None
    for att in (msg.get("attachments") or []):
        if isinstance(att, dict):
            txt = att.get("text")
            if txt and isinstance(txt, dict) and txt.get("content"):
                answer_text = txt["content"]
            qry = att.get("query")
            if qry and isinstance(qry, dict) and qry.get("query"):
                generated_sql = qry["query"]

    # 4. Try to execute the SQL against the warehouse to get the result table
    result_rows = []
    if generated_sql and WAREHOUSE_ID:
        try:
            from databricks.sdk.service.sql import Disposition, Format
            w = _w()
            stmt = w.statement_execution.execute_statement(
                warehouse_id=WAREHOUSE_ID,
                catalog="fe_bar_lakebase",
                schema="fraud_dash",
                statement=generated_sql,
                wait_timeout="30s",
                disposition=Disposition.INLINE,
                format=Format.JSON_ARRAY,
            )
            if (stmt.status and stmt.status.state
                    and str(stmt.status.state).endswith("SUCCEEDED")
                    and stmt.result and stmt.result.data_array):
                cols = [c.name for c in stmt.manifest.schema.columns]
                result_rows = [dict(zip(cols, row)) for row in stmt.result.data_array]
        except Exception as ex:
            _log("ask_genie", "result_fetch_error", 0, False, error=str(ex)[:200])

    return {
        "conv_id":       conv_id,
        "msg_id":        msg_id,
        "status":        msg.get("status", "UNKNOWN"),
        "answer_text":   answer_text,
        "generated_sql": generated_sql,
        "result_rows":   result_rows,
    }


# ---- Page: Triage Queue ---------------------------------------------------
def _page_triage_queue() -> None:
    st.subheader("Triage Queue")
    st.caption(
        f"Top {TRIAGE_LIMIT} block/review transactions  ·  "
        f"block \u2265 {BLOCK_THRESHOLD:.4f}  ·  review \u2265 {REVIEW_THRESHOLD:.4f}"
    )

    with st.sidebar:
        st.markdown("**Filters**")
        f_action = st.multiselect(
            "Recommended action", ["block", "review"],
            default=["block", "review"], key="f_action",
        )
        f_queue = st.multiselect(
            "Assigned queue", ["auto_block", "analyst_review"],
            default=["auto_block", "analyst_review"], key="f_queue",
        )
        f_case = st.selectbox(
            "Case status", ["all", "open", "closed", "no case"], index=0, key="f_case",
        )
        f_txn = st.text_input("txn_id contains", "", key="f_txn")

    lc = _lc()
    try:
        rows = lc.query(
            """
            SELECT
                r.txn_id,
                r.risk_score::float                          AS risk_score,
                r.recommended_action,
                CASE r.recommended_action
                    WHEN 'block'  THEN 'auto_block'
                    WHEN 'review' THEN 'analyst_review'
                    ELSE 'auto_approve'
                END                                          AS assigned_queue,
                r.top_shap_signals,
                fc.case_id::text                             AS case_id,
                COALESCE(fc.status, 'no case')               AS case_status
            FROM fraud_gov.txn_risk_current r
            LEFT JOIN cases.fraud_cases fc
              ON fc.txn_id = r.txn_id AND fc.status <> 'closed'
            WHERE r.recommended_action IN ('block', 'review')
            ORDER BY r.risk_score DESC
            LIMIT %s
            """,
            (TRIAGE_LIMIT,),
        )
    except Exception as exc:
        st.error(f"Failed to load triage queue: {exc}")
        return

    import pandas as pd

    display = []
    for r in rows:
        action = r.get("recommended_action", "")
        queue  = r.get("assigned_queue", "")
        cs     = r.get("case_status") or "no case"
        txnid  = r.get("txn_id", "")

        if f_action and action not in f_action:
            continue
        if f_queue and queue not in f_queue:
            continue
        if f_case != "all" and cs != f_case:
            continue
        if f_txn and f_txn not in txnid:
            continue

        try:
            sigs = json.loads(r.get("top_shap_signals") or "[]")
            top3 = ", ".join(
                f"{s['feature']}={float(s.get('shap', 0)):+.2f}"
                for s in sorted(sigs, key=lambda x: -abs(float(x.get("shap") or 0)))[:3]
            )
        except Exception:
            top3 = ""

        display.append({
            "txn_id":        txnid,
            "risk_score":    round(float(r.get("risk_score") or 0), 4),
            "action":        action,
            "queue":         queue,
            "top_3_signals": top3,
            "case_id":       r.get("case_id") or "",
            "case_status":   cs,
        })

    if not display:
        st.info("No transactions match the current filters.")
        return

    st.dataframe(pd.DataFrame(display), use_container_width=True, hide_index=True)
    st.caption(f"Showing {len(display)} transactions.")


# ---- Page: Transaction Detail ---------------------------------------------
def _page_transaction_detail() -> None:
    st.subheader("Transaction Detail")

    lc = _lc()
    try:
        id_rows = lc.query(
            """
            SELECT txn_id
            FROM fraud_gov.txn_risk_current
            WHERE recommended_action IN ('block', 'review')
            ORDER BY risk_score DESC
            LIMIT 200
            """
        )
        txn_ids = [r["txn_id"] for r in id_rows]
    except Exception as exc:
        st.error(f"Could not load transaction list: {exc}")
        return

    txn_id = st.selectbox("Select transaction", txn_ids, key="detail_txn")
    if not txn_id:
        return

    col1, col2 = st.columns(2)

    # ResponsesAgentResponse.output items carry text in content[i]["text"] (no .text attribute)
    def _resp_text(resp) -> str:
        parts = []
        for item in resp.output or []:
            for c in (getattr(item, "content", None) or []):
                t = c.get("text") if isinstance(c, dict) else getattr(c, "text", None)
                if t:
                    parts.append(t)
        return "\n\n".join(parts)

    # ---- Explain -----------------------------------------------------------
    if col1.button("\U0001f50d Explain", key="btn_explain"):
        from mlflow.types.responses import ResponsesAgentRequest
        agent = _agent()
        t0, ok = time.monotonic(), True
        try:
            with st.spinner("Running agent explanation…"):
                req = ResponsesAgentRequest(input=[{
                    "role": "user",
                    "content": (
                        f"Explain transaction {txn_id}. "
                        "Why was it flagged? What is the recommended action? "
                        "What is the calibrated confidence level and observed precision? "
                        "Which queue is it routed to?"
                    ),
                }])
                resp = agent.predict(req)
                text = _resp_text(resp) or "No response."
            st.session_state[f"explain_{txn_id}"] = text
        except Exception as exc:
            st.error(f"Agent error: {exc}")
            ok = False
            text = ""
        _log("transaction_detail", "explain",
             int((time.monotonic() - t0) * 1000), ok, txn_id=txn_id)

    if f"explain_{txn_id}" in st.session_state:
        st.markdown("**Agent explanation:**")
        st.markdown(st.session_state[f"explain_{txn_id}"])

    # ---- Open case ---------------------------------------------------------
    if col2.button("\U0001f4cb Open Case", key="btn_open_case"):
        from mlflow.types.responses import ResponsesAgentRequest
        agent = _agent()
        t0, ok = time.monotonic(), True
        case_id = None
        try:
            with st.spinner("Opening case…"):
                req = ResponsesAgentRequest(input=[{
                    "role": "user",
                    "content": (
                        f"Open a fraud case for transaction {txn_id}. "
                        "Use the model’s recommended action."
                    ),
                }])
                resp  = agent.predict(req)
                atext = _resp_text(resp)
                # Authoritative case_id: query directly after agent write
                cases  = lc.get_cases_for_txn(txn_id)
                case_id = cases[0]["case_id"] if cases else None
            st.session_state[f"case_{txn_id}"] = {"case_id": case_id, "text": atext}
        except Exception as exc:
            st.error(f"Case creation error: {exc}")
            ok = False
        _log("transaction_detail", "open_case",
             int((time.monotonic() - t0) * 1000), ok,
             txn_id=txn_id, case_id=case_id)

    if f"case_{txn_id}" in st.session_state:
        c = st.session_state[f"case_{txn_id}"]
        if c.get("case_id"):
            st.success(f"\u2705 Case ID: **{c['case_id']}**")
        if c.get("text"):
            st.markdown(c["text"])


# ---- Page: Ask Genie -------------------------------------------------------
def _page_ask_genie() -> None:
    st.subheader("Ask Genie \u2014 FE Bar Fraud Risk Ops")
    st.caption(
        f"Space `{GENIE_SPACE_ID}`  \u00b7  warehouse `{WAREHOUSE_ID}`  \u00b7  "
        "Sources: fraud_dash.{triage_queue, case_summary, case_actions_daily, "
        "exposure, baseline_comparison, score_distribution} + risk_score_calibration"
    )

    question = st.chat_input("Ask a question about fraud metrics, cases, or risk trends…")
    if not question:
        return

    t0, ok, result = time.monotonic(), True, {}
    try:
        with st.spinner("Asking Genie…"):
            result = _call_genie(question)

        st.markdown("**Answer:**")
        st.write(result.get("answer_text") or "*(no text answer)*")

        if result.get("generated_sql"):
            st.markdown("**Generated SQL:**")
            st.code(result["generated_sql"], language="sql")

        if result.get("result_rows"):
            import pandas as pd
            st.markdown("**Result table:**")
            st.dataframe(
                pd.DataFrame(result["result_rows"]),
                use_container_width=True, hide_index=True,
            )

        if result.get("conv_id"):
            st.caption(f"Conversation ID: `{result['conv_id']}`")

    except Exception as exc:
        st.error(f"Genie error: {exc}")
        ok = False

    _log(
        "ask_genie", "genie_query",
        int((time.monotonic() - t0) * 1000), ok,
        conversation_id=result.get("conv_id"),
        generated_sql_chars=len(result.get("generated_sql") or ""),
    )


# ---- Page: Dashboard -------------------------------------------------------
def _page_dashboard() -> None:
    st.subheader("FE Bar Fraud Ops: Triage & Action")
    st.markdown(
        "Daily KPI view: model performance, case volume, exposure by queue, "
        "and baseline comparison."
    )
    st.link_button("Open FE Bar Fraud Ops Dashboard", DASHBOARD_URL)


# ---- Main ------------------------------------------------------------------
def main() -> None:
    st.set_page_config(
        page_title="FE Bar Fraud Triage",
        page_icon="\U0001f6e1\ufe0f",
        layout="wide",
        initial_sidebar_state="expanded",
    )
    st.title("\U0001f6e1\ufe0f FE Bar Fraud Triage")
    st.markdown(
        f"*fevm-workshop-guy  \u00b7  block \u2265 {BLOCK_THRESHOLD:.4f}  "
        f"\u00b7  review \u2265 {REVIEW_THRESHOLD:.4f}  "
        "\u00b7  agent: workshop_guy_catalog.fe_bar_a0.fraud_triage_agent@champion*"
    )

    tab1, tab2, tab3, tab4 = st.tabs([
        "\U0001f4cb Triage Queue",
        "\U0001f50d Transaction Detail",
        "\U0001f4ac Ask Genie",
        "\U0001f4ca Dashboard",
    ])

    with tab1:
        _page_triage_queue()
    with tab2:
        _page_transaction_detail()
    with tab3:
        _page_ask_genie()
    with tab4:
        _page_dashboard()


if __name__ == "__main__":
    main()
