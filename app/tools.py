"""Direct Strands tool for CloudWatch Logs search.

This is the only direct @tool — infrastructure management and cost analysis
are handled by MCP servers via AgentCore Gateway.
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone

import boto3
from strands import tool
from strands.types.tools import ToolContext

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Pure business-logic helper (no framework dependency)
# ---------------------------------------------------------------------------


def _search_logs(
    session: boto3.Session,
    region: str,
    log_group: str,
    filter_pattern: str = "",
    minutes: int = 30,
) -> str:
    """Search CloudWatch Logs for recent entries."""
    minutes = max(1, min(minutes, 1440))

    logs = session.client("logs", region_name=region)

    # List available log groups when none specified
    if not log_group.strip():
        resp = logs.describe_log_groups(limit=25)
        groups = resp.get("logGroups", [])
        if not groups:
            return "No log groups found in this region."
        lines = ["Available log groups:"]
        for g in groups:
            lines.append(f"  - {g['logGroupName']}")
        return "\n".join(lines)

    start_ms = int((datetime.now(timezone.utc) - timedelta(minutes=minutes)).timestamp() * 1000)
    end_ms = int(datetime.now(timezone.utc).timestamp() * 1000)

    kwargs: dict = {
        "logGroupName": log_group,
        "startTime": start_ms,
        "endTime": end_ms,
        "limit": 50,
    }
    if filter_pattern.strip():
        kwargs["filterPattern"] = filter_pattern

    resp = logs.filter_log_events(**kwargs)
    events = resp.get("events", [])

    if not events:
        return (
            f"No log events found in '{log_group}' "
            f"(last {minutes} min, filter: '{filter_pattern or 'none'}')"
        )

    lines = [
        f"Logs from '{log_group}' (last {minutes} min, {len(events)} events):"
    ]
    for event in events:
        ts = datetime.fromtimestamp(
            event["timestamp"] / 1000, tz=timezone.utc
        ).strftime("%H:%M:%S")
        msg = event["message"].strip()
        if len(msg) > 300:
            msg = msg[:300] + "..."
        lines.append(f"  [{ts}] {msg}")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# @tool wrapper (Strands Agent interface)
# ---------------------------------------------------------------------------


@tool(context=True)
def search_logs(
    log_group: str, filter_pattern: str, minutes: int, tool_context: ToolContext
) -> str:
    """Search CloudWatch Logs for recent entries. Pass an empty log_group to
    list available log groups.

    Args:
        log_group: CloudWatch log group name. Pass empty string to list groups.
        filter_pattern: CloudWatch filter pattern (e.g. "ERROR", "timeout"). Empty for all.
        minutes: How many minutes back to search (1-1440).
    """
    session = boto3.Session()
    region = session.region_name or "eu-central-1"
    result = _search_logs(session, region, log_group, filter_pattern, minutes)
    state = tool_context.invocation_state
    state.setdefault("tool_calls", []).append(
        {"tool": "search_logs", "args": {"log_group": log_group, "filter_pattern": filter_pattern, "minutes": minutes}}
    )
    return result
