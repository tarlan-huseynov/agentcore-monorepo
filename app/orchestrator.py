"""Infrastructure Bootstrapper orchestrator.

Creates a fresh Strands Agent per query with MCP tools (via AgentCore Gateway)
and a direct search_logs tool, plus optional AgentCore Memory for multi-turn
session persistence.

Architecture:
    Agent Runtime (this) → AgentCore Gateway → CCAPI MCP Server (14 tools)
                                             → Cost Explorer MCP Server (7 tools)
                         → Direct @tool      → search_logs (CloudWatch Logs)
"""

from __future__ import annotations

import logging
import os
import re
import uuid
from typing import Any

from strands import Agent

from app.bedrock import create_model
from app.config import GATEWAY_URL, MEMORY_SUMMARIZATION_STRATEGY_ID, get_aws_session, get_memory_id
from app.tools import search_logs

logger = logging.getLogger(__name__)

_UNSAFE_MEMORY_ID_RE = re.compile(r"[^a-zA-Z0-9_-]")

SYSTEM_PROMPT = """\
You are an Infrastructure Bootstrapper Agent running on Amazon Bedrock AgentCore.
You create, modify, and manage real AWS infrastructure from natural language using
the Cloud Control API (via MCP), analyze costs, and search logs.

## Creating a Resource (2 steps)

1. prepare_resource_creation(resource_type, properties, region)
   → Returns 'explanation' and 'desired_state'. Show the explanation to the user.
2. After user approves: confirm_resource_creation(resource_type, desired_state, region)
   → Pass the desired_state, resource_type, and region from step 1 exactly.

Example — create an SQS queue:
  Step 1: prepare_resource_creation(resource_type="AWS::SQS::Queue",
            properties={"QueueName": "my-queue"})
  Step 2: confirm_resource_creation(resource_type="AWS::SQS::Queue",
            desired_state=<from step 1>, region=<from step 1>)

## Deleting a Resource (2 steps)

1. prepare_resource_deletion(resource_type, identifier, region)
   → Returns 'explanation' and current resource details. Show to user.
2. After user approves: confirm_resource_deletion(resource_type, identifier, region)

## Read-Only Operations (single step, no confirmation needed)

- list_resources: List resources of a given type (e.g. AWS::S3::Bucket)
- get_resource: Get details of a specific resource by identifier
- get_resource_schema_information: Get Cloud Control schema for a resource type
- get_resource_request_status: Check status of an async resource operation
- create_template: Generate a CloudFormation template from existing resources
- get_aws_account_info: Quick account/session info

## Cost Analysis

- get_today_date: Get today's date (anchor for relative date ranges)
- get_cost_and_usage: Spending breakdown by service, tag, or account
- get_cost_forecast: Projected spend for a future date range
- get_dimension_values: Valid values for a Cost Explorer dimension
- get_tag_values: All values for a cost allocation tag key
- get_cost_and_usage_comparisons: Side-by-side comparison across periods
- get_cost_comparison_drivers: What's driving cost changes between periods

## Log Search (direct tool)

- search_logs: Search CloudWatch Logs. Pass empty log_group to list available groups.

## IMPORTANT Rules

- For create/delete: ALWAYS use the prepare_ + confirm_ tools (NOT the raw
  create_resource/delete_resource/update_resource tools — they require a multi-step
  token chain that does not work in stateless mode).
- ALWAYS show the explanation to the user before confirming a create or delete.
- NEVER fabricate desired_state — always pass it exactly from prepare_resource_creation.
- Confirm destructive actions (deletion) with the user before calling confirm_.
"""

_SENTINEL = object()

# Stable agent ID so the session manager can find previous conversations.
# Without this, each fresh Agent() gets a random UUID and the session manager
# treats every invocation as a brand-new agent (no history restored).
_AGENT_ID = "bootstrapper"


def _sanitize_memory_id(value: str) -> str:
    """Replace characters not allowed by AgentCore Memory API.

    AgentCore requires sessionId/actorId to match [a-zA-Z0-9][a-zA-Z0-9-_]*.
    Slack IDs and other external IDs may contain colons or other characters.
    """
    sanitized = _UNSAFE_MEMORY_ID_RE.sub("-", value)
    if not sanitized or not sanitized[0].isalnum():
        sanitized = "s" + sanitized
    return sanitized


def _create_mcp_client():
    """Create an MCPClient connected to the AgentCore Gateway, or None."""
    if not GATEWAY_URL:
        logger.info("GATEWAY_URL not set — MCP tools unavailable")
        return None

    from strands.tools.mcp import MCPClient
    from mcp.client.streamable_http import streamablehttp_client

    logger.info("Creating MCPClient for Gateway: %s", GATEWAY_URL)
    return MCPClient(lambda: streamablehttp_client(url=GATEWAY_URL))


class DemoOrchestrator:
    """Single entry point for answering user queries.

    Creates a fresh strands.Agent per query (no state leakage).
    Connects to AgentCore Gateway for MCP tools (CCAPI + Cost Explorer).
    Optionally integrates AgentCore Memory for multi-turn sessions.
    """

    def __init__(
        self,
        model: Any | None = None,
        memory_id: Any = _SENTINEL,
    ) -> None:
        self._model = model or create_model()
        self._memory_id = get_memory_id() if memory_id is _SENTINEL else memory_id
        self._gateway_enabled = bool(GATEWAY_URL)

    def _create_session_manager(
        self, session_id: str, actor_id: str
    ) -> Any | None:
        """Create an AgentCoreMemorySessionManager if memory is enabled."""
        if not self._memory_id:
            return None

        safe_session = _sanitize_memory_id(session_id)
        safe_actor = _sanitize_memory_id(actor_id)
        logger.info(
            "Creating session manager: memory_id=%s session=%s actor=%s",
            self._memory_id,
            safe_session,
            safe_actor,
        )

        # Deferred import: bedrock_agentcore.memory pulls in heavy deps.
        # Importing at module level would exceed the 30-second AgentCore
        # initialization timeout.
        from bedrock_agentcore.memory.integrations.strands.config import (
            AgentCoreMemoryConfig,
            RetrievalConfig,
        )
        from bedrock_agentcore.memory.integrations.strands.session_manager import (
            AgentCoreMemorySessionManager,
        )

        retrieval_config = None
        if MEMORY_SUMMARIZATION_STRATEGY_ID:
            namespace = (
                "strategies/{memoryStrategyId}"
                "/actors/{actorId}"
                "/sessions/{sessionId}"
            )
            retrieval_config = {
                namespace: RetrievalConfig(
                    strategy_id=MEMORY_SUMMARIZATION_STRATEGY_ID,
                    top_k=5,
                ),
            }

        config = AgentCoreMemoryConfig(
            memory_id=self._memory_id,
            session_id=safe_session,
            actor_id=safe_actor,
            retrieval_config=retrieval_config,
        )

        boto_session = get_aws_session()
        region = os.getenv("AWS_REGION") or boto_session.region_name

        return AgentCoreMemorySessionManager(
            agentcore_memory_config=config,
            region_name=region,
            boto_session=boto_session,
        )

    def _run_agent(
        self,
        query: str,
        tools: list,
        session_manager: Any | None,
    ) -> tuple[Any, dict[str, Any], bool, int]:
        """Run the Strands agent loop, retrying without memory on corruption."""
        memory_enabled = session_manager is not None
        state: dict[str, Any] = {"tool_calls": []}

        agent = Agent(
            model=self._model,
            tools=tools,
            system_prompt=SYSTEM_PROMPT,
            session_manager=session_manager,
            callback_handler=None,
            agent_id=_AGENT_ID,
        )

        restored_messages = len(agent.messages)
        logger.info(
            "Agent created: agent_id=%s, restored_messages=%d",
            _AGENT_ID,
            restored_messages,
        )

        try:
            result = agent(query, invocation_state=state)
        except Exception as exc:
            # Bedrock Converse API: every toolResult must have matching toolUse.
            # Session memory can inject orphaned toolResults, breaking the API.
            if "toolResult" in str(exc) and "toolUse" in str(exc):
                logger.warning("Memory corruption — retrying without memory")
                agent = Agent(
                    model=self._model,
                    tools=tools,
                    system_prompt=SYSTEM_PROMPT,
                    callback_handler=None,
                    agent_id=_AGENT_ID,
                )
                state = {"tool_calls": []}
                memory_enabled = False
                result = agent(query, invocation_state=state)
            else:
                raise
        finally:
            # Flush any buffered messages to AgentCore Memory.
            if session_manager is not None and hasattr(session_manager, "close"):
                try:
                    session_manager.close()
                except Exception as close_exc:
                    logger.warning("Session manager close failed: %s", close_exc)

        return result, state, memory_enabled, restored_messages

    def ask(
        self,
        query: str,
        session_id: str | None = None,
        actor_id: str | None = None,
    ) -> dict[str, Any]:
        """Answer a user query using the Strands agent loop.

        Returns dict with answer, stop_reason, tool_calls, and memory metadata.
        """
        session_id = session_id or str(uuid.uuid4())
        actor_id = actor_id or "anonymous"

        # Memory — graceful degradation on failure
        try:
            session_manager = self._create_session_manager(session_id, actor_id)
        except Exception as exc:
            logger.info("Memory init failed (proceeding without): %s", exc)
            session_manager = None

        memory_enabled = session_manager is not None
        logger.info("Creating agent (memory=%s, gateway=%s)", memory_enabled, self._gateway_enabled)

        direct_tools = [search_logs]

        if self._gateway_enabled:
            # Gateway mode: fresh MCPClient per invocation to avoid
            # "client session is currently running" on concurrent requests.
            mcp_client = _create_mcp_client()
            with mcp_client:
                all_tools = mcp_client.list_tools_sync() + direct_tools
                result, state, memory_enabled, restored = self._run_agent(
                    query, all_tools, session_manager
                )
        else:
            # Fallback: direct tools only (no Gateway)
            result, state, memory_enabled, restored = self._run_agent(
                query, direct_tools, session_manager
            )

        return {
            "answer": str(result),
            "stop_reason": result.stop_reason,
            "tool_calls": state.get("tool_calls", []),
            "memory": {
                "enabled": memory_enabled,
                "restored_messages": restored,
                "session_id": session_id,
                "actor_id": actor_id,
            },
        }
