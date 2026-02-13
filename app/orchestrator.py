"""Demo orchestrator -- simplified version of AthenaOrchestrator.

Creates a fresh Strands Agent per query with optional AgentCore Memory
integration for multi-turn session persistence.
"""

from __future__ import annotations

import logging
import re
import uuid
from typing import Any

from strands import Agent

from app.bedrock import create_model
from app.config import MEMORY_SUMMARIZATION_STRATEGY_ID, get_aws_session, get_memory_id
from app.tools import get_time, get_weather, tell_joke

logger = logging.getLogger(__name__)

_UNSAFE_MEMORY_ID_RE = re.compile(r"[^a-zA-Z0-9_-]")

SYSTEM_PROMPT = """\
You are a friendly demo assistant running on Amazon Bedrock AgentCore.

You have three tools available:
- get_weather: Look up weather for a city
- get_time: Look up the current time in a timezone
- tell_joke: Tell a joke about a topic

Use the right tool for each request. If a question does not need a tool,
answer directly from your knowledge.

Keep responses concise and helpful.
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


class DemoOrchestrator:
    """Single entry point for answering user queries.

    Creates a fresh strands.Agent per query (no state leakage).
    Optionally integrates AgentCore Memory for multi-turn sessions.
    """

    def __init__(
        self,
        model: Any | None = None,
        memory_id: Any = _SENTINEL,
    ) -> None:
        self._model = model or create_model()
        self._memory_id = get_memory_id() if memory_id is _SENTINEL else memory_id

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
        logger.info("Creating agent (memory=%s)", memory_enabled)

        tools = [get_weather, get_time, tell_joke]
        agent = Agent(
            model=self._model,
            tools=tools,
            system_prompt=SYSTEM_PROMPT,
            session_manager=session_manager,
            callback_handler=None,
        )

        state: dict[str, Any] = {"tool_calls": []}

        try:
            result = agent(query, invocation_state=state)
        except Exception as exc:
            # Bedrock Converse API: every toolResult must have matching toolUse.
            # Session memory can inject orphaned toolResults, breaking the API.
            # Retry without memory on this specific error.
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
