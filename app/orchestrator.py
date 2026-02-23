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

## Available Tools

### Infrastructure Management (via CCAPI MCP Server — Gateway)
- check_environment_variables: Verify AWS credentials and region config
- get_aws_session_info: Get current AWS session details
- get_aws_account_info: Get AWS account information
- get_resource_schema_information: Get Cloud Control schema for a resource type
- list_resources: List resources of a given type (e.g. AWS::S3::Bucket)
- get_resource: Get details of a specific resource
- create_resource: Create a new AWS resource via Cloud Control API
- update_resource: Update an existing resource
- delete_resource: Delete a resource
- get_resource_request_status: Check status of an async resource operation
- generate_infrastructure_code: Generate IaC code (CloudFormation/Terraform/CDK)
- explain: Explain infrastructure concepts or resource configurations
- create_template: Create a CloudFormation template
- run_checkov: Run security scanning on generated code

### Cost Analysis (via Cost Explorer MCP Server — Gateway)
- get_today_date: Get today's date for cost queries
- get_cost_and_usage: Get cost and usage data with filters
- get_cost_forecast: Forecast future costs
- get_dimension_values: Get available dimension values for filtering
- get_tag_values: Get available tag values for filtering
- get_cost_and_usage_comparisons: Compare costs across time periods
- get_cost_comparison_drivers: Identify what's driving cost changes

### Log Search (direct tool)
- search_logs: Search CloudWatch Logs (pass empty log_group to list groups)

## Workflows

**Create infrastructure:**
1. Use check_environment_variables to verify AWS setup
2. Get the resource schema with get_resource_schema_information
3. Create the resource with create_resource
4. Verify with get_resource

**List/inspect resources:**
1. Use list_resources with the resource type (e.g. AWS::DynamoDB::Table)
2. Use get_resource for detailed info on a specific resource

**Generate infrastructure code:**
1. Use generate_infrastructure_code for CloudFormation/Terraform/CDK templates
2. Use run_checkov to validate security
3. Use explain to describe what the code does

**Analyze costs:**
1. Use get_today_date to anchor time-based queries
2. Use get_cost_and_usage for spending breakdowns
3. Use get_cost_forecast for future projections

## Safety Rules
- Always verify AWS credentials before making changes
- Use run_checkov to scan generated code for security issues
- Confirm destructive actions (delete_resource) with the user first
- Explain what each operation will do before executing
"""

_SENTINEL = object()


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
        self._mcp_client = _create_mcp_client()

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
        return AgentCoreMemorySessionManager(
            agentcore_memory_config=config,
            boto_session=get_aws_session(),
        )

    def _run_agent(
        self,
        query: str,
        tools: list,
        session_manager: Any | None,
    ) -> tuple[Any, dict[str, Any], bool]:
        """Run the Strands agent loop, retrying without memory on corruption."""
        memory_enabled = session_manager is not None
        state: dict[str, Any] = {"tool_calls": []}

        agent = Agent(
            model=self._model,
            tools=tools,
            system_prompt=SYSTEM_PROMPT,
            session_manager=session_manager,
            callback_handler=None,
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
                )
                state = {"tool_calls": []}
                memory_enabled = False
                result = agent(query, invocation_state=state)
            else:
                raise

        return result, state, memory_enabled

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
        logger.info("Creating agent (memory=%s, gateway=%s)", memory_enabled, bool(self._mcp_client))

        direct_tools = [search_logs]

        if self._mcp_client:
            # Gateway mode: MCP tools + direct tools
            with self._mcp_client:
                all_tools = self._mcp_client.list_tools_sync() + direct_tools
                result, state, memory_enabled = self._run_agent(
                    query, all_tools, session_manager
                )
        else:
            # Fallback: direct tools only (no Gateway)
            result, state, memory_enabled = self._run_agent(
                query, direct_tools, session_manager
            )

        return {
            "answer": str(result),
            "stop_reason": result.stop_reason,
            "tool_calls": state.get("tool_calls", []),
            "memory": {
                "enabled": memory_enabled,
                "session_id": session_id,
                "actor_id": actor_id,
            },
        }
