"""
fraud_triage_agent.py — Fraud Triage Copilot (ResponsesAgent)

Tool-calling agent on Mosaic AI Agent Framework + Foundation Model API.
Uses UCFunctionToolkit for read tools and an agent-side Python tool for
create_fraud_case (because UC functions cannot connect to Lakebase).
"""

import json
import mlflow
from mlflow.pyfunc import ResponsesAgent
from mlflow.types.responses import (
    ResponsesAgentRequest,
    ResponsesAgentResponse,
    ResponsesAgentStreamEvent,
)
from databricks_langchain import ChatDatabricks, UCFunctionToolkit
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
UC_FUNCTIONS = [
    "workshop_guy_catalog.fe_bar_a0.get_transaction_risk",
    "workshop_guy_catalog.fe_bar_a0.explain_top_signals",
    "workshop_guy_catalog.fe_bar_a0.get_customer_history",
]

SYSTEM_PROMPT = """You are the Fraud Triage Copilot, an AI assistant that helps fraud analysts understand and act on flagged transactions.

RULES:
1. ALWAYS call get_transaction_risk AND explain_top_signals BEFORE saying anything about a transaction. Never invent scores, features, or history.
2. The model's recommended_action is the default. You may disagree and explain why, but open the case with the model's action unless the user explicitly overrides it. Record any override in the notes.
3. Only call create_fraud_case when the user asks to open a case or act. Never create cases during plain explanation.
4. For each transaction, output:
   - Why flagged (plain language, top signals)
   - Recommended action
   - Confidence level
   - Routed queue
   - Customer context (call get_customer_history)
   - Suggested next step
5. If a transaction ID is not found, say so clearly. Do not invent data.
6. An approve-band transaction should not be pushed into block. Respect the model's scoring bands."""

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
        # UC function tools
        uc_tools = list(UCFunctionToolkit(function_names=UC_FUNCTIONS).tools)
        # Agent-side tool
        self.all_tools = uc_tools + [create_fraud_case]
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
