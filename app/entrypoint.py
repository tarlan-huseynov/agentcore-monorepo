"""Amazon Bedrock AgentCore Runtime entry point.

Local usage:
    python app/entrypoint.py       # starts HTTP server on :8080

    curl -X POST http://localhost:8080/invocations \
      -H "Content-Type: application/json" \
      -d '{"prompt": "What is the weather in Tokyo?"}'
"""

from __future__ import annotations

import logging
import os
import sys
import traceback

# Ensure project root is on the Python path so ``from app.xxx`` imports work
# both locally and inside the AgentCore deployment ZIP.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# OpenTelemetry discovers its context runtime via importlib entry_points,
# which requires .dist-info directories.  Our packaging keeps them, but set
# the context implementation explicitly as a safety net.
os.environ.setdefault("OTEL_PYTHON_CONTEXT", "contextvars_context")

from bedrock_agentcore.runtime import BedrockAgentCoreApp  # noqa: E402

# IMPORTANT: Do NOT import DemoOrchestrator at module level.
# The import chain (strands, boto3, pydantic, etc.) is too heavy for the
# AgentCore 30-second initialization timeout.  We defer to first invocation.

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(name)s %(levelname)s %(message)s",
)
logger = logging.getLogger(__name__)

app = BedrockAgentCoreApp()

_orchestrator = None


def _get_orchestrator():
    """Lazy-initialize on first invocation (deferred heavy imports)."""
    global _orchestrator
    if _orchestrator is None:
        logger.info("Importing DemoOrchestrator (deferred)...")
        from app.orchestrator import DemoOrchestrator

        _orchestrator = DemoOrchestrator()
        logger.info("DemoOrchestrator ready.")
    return _orchestrator


@app.entrypoint
def invoke(payload: dict) -> dict:
    """Process an AgentCore invocation.

    Expected payload::

        {
            "prompt": "What's the weather in Tokyo?",
            "session_id": "optional-session-id",
            "actor_id": "optional-actor-id"
        }
    """
    try:
        logger.info("invoke() called: keys=%s", list(payload.keys()))
        orchestrator = _get_orchestrator()

        prompt = payload.get("prompt", "")
        if not prompt:
            return {"answer": "No prompt provided.", "stop_reason": "error"}

        result = orchestrator.ask(
            query=prompt,
            session_id=payload.get("session_id"),
            actor_id=payload.get("actor_id"),
        )

        logger.info(
            "Response: stop_reason=%s answer_len=%d tools=%d",
            result.get("stop_reason"),
            len(result.get("answer", "")),
            len(result.get("tool_calls", [])),
        )
        return result

    except Exception as exc:
        tb = traceback.format_exc()
        logger.error("invoke() failed: %s\n%s", exc, tb)
        return {"answer": f"Error: {exc}", "stop_reason": "error"}


if __name__ == "__main__":
    app.run()
