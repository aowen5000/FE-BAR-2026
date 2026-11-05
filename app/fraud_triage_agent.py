"""
fraud_triage_agent.py: Fraud Triage Copilot (ResponsesAgent)

Tool-calling agent on Mosaic AI Agent Framework + Foundation Model API.

Governance rule (FGAC hardening, 2026-10-21): every tool is governed by UC or
by Postgres, never neither. The UC SQL functions in agent_tools.sql read the
ungoverned synced tables (fe_bar_lakebase.fraud.*). Through UC, the fraud_gov
views filter every caller the same way because pg_has_role() is evaluated for
the UC service role, not the end user, so they are not identity-aware there.
All four tools are therefore agent-side Python tools. They connect directly to
Lakebase as LakebaseCases(pg_role='fraud_triage_agent') and read only fraud_gov.*
plus the RLS-protected cases.* tables. The UC functions are deprecated and NOT
registered with the agent.
"""

import json
import mlflow
from mlflow.pyfunc import ResponsesAgent
from mlflow.types.responses import (
    ResponsesAgentRequest,
    ResponsesAgentResponse,
    ResponsesAgentStreamEvent,
)
from databricks_langchain import ChatDatabricks
from langchain_core.messages import AIMessage, SystemMessage, HumanMessage, ToolMessage
from langchain_core.tools import tool
from langchain_core.runnables import RunnableLambda
from langgraph.graph import END, StateGraph
from langgraph.graph.message import add_messages
from langgraph.prebuilt.tool_node import ToolNode
from typing import Annotated, Sequence, TypedDict

import sys
sys.path.insert(0, "/Workspace/Users/alex.owen@databricks.com/FE-BAR-2026-repo")

# ---- Configuration --------------------------------------------------------
LLM_ENDPOINT = "databricks-claude-sonnet-5-5"
AGENT_PG_ROLE = "fraud_triage_agent"
TOOL_IMPL = "agent_python:postgres:fraud_triage_agent"

# Shared, lazily created governed connection for the read tools.
_READER = None


def _reader():
    global _READER
    if _READER is None:
        from lakebase_cases import LakebaseCases
        _READER = LakebaseCases(pg_role=AGENT_PG_ROLE)
    return _READER


def _jsonable(rows):
    out = []
    for r in rows:
        out.append({k: (v.isoformat() if hasattr(v, "isoformat") else (float(v) if hasattr(v, "as_tuple") else v)) for k, v in r.items()})
    return out


def _envelope(tool_name, objects_read, rows):
    """Wrap tool output with provenance so traces show which implementation ran
    and which objects it read."""
    return json.dumps({
        "_tool": tool_name,
        "_implementation": TOOL_IMPL,
        "_objects_read": objects_read,
        "rows": _jsonable(rows),
    }, default=str)

SYSTEM_PROMPT = """You are the Fraud Triage Copilot, an AI assistant that helps fraud analysts understand and act on flagged transactions.

RULES:
1. ALWAYS call get_transaction_risk AND explain_top_signals BEFORE saying anything about a transaction. Never invent scores, features, or history.
2. The model's recommended_action is the default. You may disagree and explain why, but open the case with the model's action unless the user explicitly overrides it. Record any override in the notes.
3. Only call create_fraud_case when the user asks to open a case or act. Never create cases during plain explanation.
4. For each transaction, output:
   - Why flagged (plain language, top signals)
   - Recommended action
   - Confidence level, with the observed precision number from get_transaction_risk (confidence_display)
   - Routed queue
   - Customer context (call get_customer_history)
   - Suggested next step
5. If a transaction ID is not found, say so clearly. Do not invent data.
6. An approve-band transaction should not be pushed into block. Respect the model's scoring bands."""

# ---- Agent-side read tools (Postgres-governed) ------------------------------
# Names, signatures and docstrings match the deprecated UC functions.

@tool
def get_transaction_risk(txn_id: str) -> str:
    """Returns the risk assessment for a single transaction including risk score, recommended action, confidence (high/medium/low) with the observed precision of its calibration bucket, and routed queue (auto_block/analyst_review/auto_approve)."""
    objs = ["fraud_gov.txn_risk_current", "fraud_gov.txn_features", "fraud_gov.risk_score_calibration"]
    rows = _reader().query(
        """
        SELECT r.txn_id, r.customer_id, f.txn_ts, f.amount, r.risk_score,
               r.recommended_action, r.model_version, r.scored_at,
               c.confidence, c.observed_precision, c.bucket AS calibration_bucket,
               c.row_count AS calibration_bucket_rows,
               CASE r.recommended_action WHEN 'block' THEN 'auto_block'
                    WHEN 'review' THEN 'analyst_review'
                    WHEN 'approve' THEN 'auto_approve' END AS routed_queue
        FROM fraud_gov.txn_risk_current r
        JOIN fraud_gov.txn_features f ON f.txn_id = r.txn_id
        LEFT JOIN fraud_gov.risk_score_calibration c
          ON r.risk_score >= c.lower_bound
         AND (r.risk_score < c.upper_bound OR (c.bucket = 'block_band' AND r.risk_score <= c.upper_bound))
        WHERE r.txn_id = %s
        """,
        (txn_id,),
    )
    for r in rows:
        if r.get("observed_precision") is not None:
            r["confidence_display"] = f"{r['confidence']} (observed precision {float(r['observed_precision']):.2f} in {r['calibration_bucket']}, n={r['calibration_bucket_rows']})"
    return _envelope("get_transaction_risk", objs, rows)


@tool
def explain_top_signals(txn_id: str) -> str:
    """Returns the top SHAP signals for a scored transaction as plain-language explanations with SHAP values and customer context."""
    objs = ["fraud_gov.txn_risk_current", "fraud_gov.txn_features", "fraud_gov.customer_risk_profile"]
    base = _reader().query(
        """
        SELECT r.txn_id, r.top_shap_signals, c.distinct_devices_30d, c.home_region,
               c.txn_count_30d, c.avg_amount_30d
        FROM fraud_gov.txn_risk_current r
        JOIN fraud_gov.txn_features f ON f.txn_id = r.txn_id
        LEFT JOIN fraud_gov.customer_risk_profile c ON c.customer_id = f.customer_id
        WHERE r.txn_id = %s
        """,
        (txn_id,),
    )
    def _num(v):
        # Coerce to float; None for None/empty/non-numeric (e.g. categorical risk_segment='high').
        if v is None or v == "":
            return None
        try:
            return float(v)
        except (TypeError, ValueError):
            return None

    def _fmt(v, spec):
        # Numeric values use the format spec; anything else is shown as text.
        n = _num(v)
        return format(n, spec) if n is not None else ("n/a" if v is None or v == "" else str(v))

    rows = []
    for b in base:
        sigs = json.loads(b["top_shap_signals"] or "[]")
        for s in sorted(sigs, key=lambda x: -(_num(x.get("shap")) or 0.0)):
            feat, val, shap = s["feature"], s.get("value"), (_num(s.get("shap")) or 0.0)
            if feat == "is_new_device":
                fv, normal = _fmt(val, ".0f"), f"Customer uses {b['distinct_devices_30d']} devices in 30d"
                expl = (f"New device (SHAP +{shap:.2f}). Normally uses {b['distinct_devices_30d']} devices." if _num(val) == 1 else "Known device.")
            elif feat == "geo_distance_from_home":
                fv, normal = f"{_fmt(val, '.1f')} km", f"Home region: {b['home_region']}"
                expl = f"{_fmt(val, '.1f')} km from home ({b['home_region']}), SHAP +{shap:.2f}."
            elif feat == "is_online":
                fv, normal = _fmt(val, ".0f"), f"Customer avg 30d txns: {b['txn_count_30d']}"
                expl = (f"Online txn (SHAP +{shap:.2f}). Higher risk." if _num(val) == 1 else "In-person.")
            elif feat == "amount":
                avg = _num(b["avg_amount_30d"]) or 0.0
                fv, normal = f"${_fmt(val, '.2f')}", f"Avg 30d: ${avg:.2f}"
                expl = f"${_fmt(val, '.2f')} vs avg ${avg:.2f} (SHAP +{shap:.2f})."
            else:
                fv, normal = _fmt(val, ".4f"), "See customer profile"
                expl = f"{feat} = {_fmt(val, '.4f')} (SHAP +{shap:.2f})"
            rows.append({"txn_id": b["txn_id"], "signal_name": feat, "shap_value": shap,
                         "feature_value": fv, "customer_normal": normal, "explanation": expl})
    return _envelope("explain_top_signals", objs, rows)


@tool
def get_customer_history(customer_id: str) -> str:
    """Returns customer risk profile, last 20 transactions with risk scores, prior fraud outcome counts, and existing fraud cases."""
    objs = ["fraud_gov.customer_risk_profile", "fraud_gov.txn_risk_current", "fraud_gov.txn_features", "cases.fraud_cases"]
    rd = _reader()
    rows = []
    for p in rd.query("SELECT * FROM fraud_gov.customer_risk_profile WHERE customer_id = %s", (customer_id,)):
        rows.append({"section": "profile", "detail": " | ".join(f"{k}={v}" for k, v in p.items())})
        # Prior outcomes come from the gold profile (prior_case_count / confirmed_fraud_count),
        # which is derived from fact_prior_fraud_cases_silver in the gold pipeline.
        rows.append({"section": "prior_outcomes", "detail": f"confirmed_fraud={p['confirmed_fraud_count']} | total={p['prior_case_count']}"})
    for t in rd.query(
        """
        SELECT f.txn_id, f.amount, r.risk_score, r.recommended_action, f.txn_ts
        FROM fraud_gov.txn_features f JOIN fraud_gov.txn_risk_current r ON r.txn_id = f.txn_id
        WHERE f.customer_id = %s ORDER BY f.txn_ts DESC LIMIT 20
        """,
        (customer_id,),
    ):
        rows.append({"section": "recent_txns", "detail": f"txn_id={t['txn_id']} | amount=${float(t['amount']):.2f} | risk_score={float(t['risk_score']):.4f} | action={t['recommended_action']} | txn_ts={t['txn_ts']}"})
    for cse in rd.query(
        """
        SELECT fc.case_id, fc.txn_id, fc.status, fc.assigned_queue
        FROM cases.fraud_cases fc JOIN fraud_gov.txn_features f ON f.txn_id = fc.txn_id
        WHERE f.customer_id = %s ORDER BY fc.created_at
        """,
        (customer_id,),
    ):
        rows.append({"section": "existing_cases", "detail": f"case_id={cse['case_id']} | txn_id={cse['txn_id']} | status={cse['status']} | queue={cse['assigned_queue']}"})
    return _envelope("get_customer_history", objs, rows)


# ---- Agent-side tool: create_fraud_case -----------------------------------
@tool
def create_fraud_case(
    txn_id: str,
    action: str,
    notes: str,
) -> str:
    """Create a fraud case for a transaction in Lakebase. The case is written
    through the fraud_triage_agent Postgres role with governed access.
    Action must be one of: approve, review, block.
    Returns a JSON string with case_id and status."""
    from lakebase_cases import LakebaseCases

    queue_map = {"block": "auto_block", "review": "analyst_review", "approve": "auto_approve"}
    if action not in queue_map:
        return json.dumps({"error": f"Invalid action '{action}'. Must be approve, review, or block."})

    lc = LakebaseCases(pg_role="fraud_triage_agent")
    try:
        # Code-level guardrail (system prompt rule 6): never push an approve-band
        # transaction into block, regardless of what the caller or LLM asks for.
        band = lc.query(
            "SELECT recommended_action FROM fraud_gov.txn_risk_current WHERE txn_id = %s",
            (txn_id,),
        )
        if band and band[0]["recommended_action"] == "approve" and action == "block":
            return json.dumps({"error": f"Refused: model recommended 'approve' for {txn_id}; an approve-band transaction cannot be opened as 'block'."})
        case_id = lc.create_fraud_case(
            txn_id=txn_id,
            recommended_action=action,
            assigned_queue=queue_map[action],
            notes=notes,
            created_by="fraud_triage_copilot:agent",
        )
        return json.dumps({"case_id": case_id, "txn_id": txn_id, "action": action, "queue": queue_map[action], "status": "created"})
    except ValueError as e:
        return json.dumps({"error": str(e)})
    except Exception as e:
        return json.dumps({"error": f"Failed to create case: {str(e)}"})
    finally:
        lc.close()


# ---- LangGraph Agent -------------------------------------------------------
class State(TypedDict):
    messages: Annotated[Sequence, add_messages]


class FraudTriageAgent(ResponsesAgent):
    def __init__(self):
        self.llm = ChatDatabricks(endpoint=LLM_ENDPOINT)
        # All tools are agent-side and Postgres-governed (role fraud_triage_agent).
        # The deprecated UC functions in agent_tools.sql are intentionally NOT registered.
        self.all_tools = [get_transaction_risk, explain_top_signals, get_customer_history, create_fraud_case]
        self.llm_with_tools = self.llm.bind_tools(self.all_tools)

    def _build_graph(self):
        def call_model(state):
            msgs = [SystemMessage(content=SYSTEM_PROMPT)] + list(state["messages"])
            return {"messages": [self.llm_with_tools.invoke(msgs)]}

        def should_continue(state):
            last = state["messages"][-1]
            if isinstance(last, AIMessage) and last.tool_calls:
                return "tools"
            return "end"

        g = StateGraph(State)
        g.add_node("agent", RunnableLambda(call_model))
        g.add_node("tools", ToolNode(self.all_tools))
        g.set_entry_point("agent")
        g.add_conditional_edges("agent", should_continue, {"tools": "tools", "end": END})
        g.add_edge("tools", "agent")
        return g.compile()

    def predict(self, request: ResponsesAgentRequest) -> ResponsesAgentResponse:
        graph = self._build_graph()
        # Convert input to LangChain messages
        lc_msgs = []
        for item in request.input:
            d = item.model_dump() if hasattr(item, 'model_dump') else item
            role = d.get("role", "user")
            content = d.get("content", "")
            if role == "user":
                lc_msgs.append(HumanMessage(content=content))
            elif role == "assistant":
                lc_msgs.append(AIMessage(content=content))
            elif role == "system":
                lc_msgs.append(SystemMessage(content=content))

        result = graph.invoke({"messages": lc_msgs})
        # Extract text from the final AI message
        final_msgs = result["messages"]
        text_parts = []
        for m in reversed(final_msgs):
            if isinstance(m, AIMessage):
                content = m.content
                if isinstance(content, str) and content.strip():
                    text_parts.append(content)
                    break
                elif isinstance(content, list):
                    for block in content:
                        if isinstance(block, dict) and block.get("type") == "text":
                            text_parts.append(block["text"])
                        elif isinstance(block, str):
                            text_parts.append(block)
                    if text_parts:
                        break

        final_text = "\n".join(text_parts) if text_parts else "No response generated."
        return ResponsesAgentResponse(output=[
            self.create_text_output_item(text=final_text, id="msg_final")
        ])


mlflow.langchain.autolog()
mlflow.models.set_model(FraudTriageAgent())
