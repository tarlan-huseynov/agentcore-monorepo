#!/usr/bin/env python3
"""Remote CLI -- interactive REPL for the deployed AgentCore runtime.

Calls the deployed AgentCore runtime via boto3, passing session_id and
actor_id in the payload for memory continuity testing.

Usage:
    uv run python cli_remote.py                              # interactive
    uv run python cli_remote.py --arn "arn:aws:bedrock-agentcore:..."
    uv run python cli_remote.py -q "Weather in Tokyo?"       # single query
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import uuid as _uuid
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).parent / ".env")

import os

import boto3
from botocore.config import Config as BotoConfig

# ---------------------------------------------------------------------------
# ANSI colours
# ---------------------------------------------------------------------------
_IS_TTY = sys.stdout.isatty()


def _c(code: str, text: str) -> str:
    return f"\033[{code}m{text}\033[0m" if _IS_TTY else text


def dim(t: str) -> str:
    return _c("2", t)


def bold(t: str) -> str:
    return _c("1", t)


def green(t: str) -> str:
    return _c("32", t)


def cyan(t: str) -> str:
    return _c("36", t)


def yellow(t: str) -> str:
    return _c("33", t)


def red(t: str) -> str:
    return _c("31", t)


# ---------------------------------------------------------------------------
# Runtime invocation
# ---------------------------------------------------------------------------

def _read_body(body, debug: bool = False) -> str:
    """Read the response body from various formats into a raw string."""
    # StreamingBody (botocore)
    if hasattr(body, "read"):
        raw = body.read()
        if isinstance(raw, bytes):
            raw = raw.decode("utf-8")
        if debug:
            print(dim(f"  [debug] StreamingBody raw ({len(raw)} chars): {raw[:500]}"))
        return raw

    # EventStream -- collect all chunks
    if hasattr(body, "__iter__") and not isinstance(body, (str, bytes, dict)):
        chunks = []
        for event in body:
            if debug:
                print(dim(f"  [debug] event: {repr(event)[:300]}"))
            if isinstance(event, dict):
                for key in ("chunk", "payload", "body"):
                    if key in event:
                        val = event[key]
                        if isinstance(val, dict) and "bytes" in val:
                            chunks.append(val["bytes"].decode("utf-8"))
                        elif isinstance(val, (str, bytes)):
                            chunks.append(val if isinstance(val, str) else val.decode("utf-8"))
                        break
                else:
                    chunks.append(json.dumps(event))
        combined = "".join(chunks)
        if debug:
            print(dim(f"  [debug] EventStream combined ({len(combined)} chars): {combined[:500]}"))
        return combined

    # String
    if isinstance(body, (str, bytes)):
        raw = body if isinstance(body, str) else body.decode("utf-8")
        if debug:
            print(dim(f"  [debug] string body ({len(raw)} chars): {raw[:500]}"))
        return raw

    # Already a dict -- serialize back so caller can parse uniformly
    if isinstance(body, dict):
        return json.dumps(body)

    return str(body)


def _extract_result(data: dict) -> dict:
    """Unwrap AgentCore response envelope if needed."""
    if "answer" in data:
        return data

    for key in ("output", "result", "response", "body"):
        inner = data.get(key)
        if isinstance(inner, dict) and "answer" in inner:
            return inner
        if isinstance(inner, str):
            try:
                parsed = json.loads(inner)
                if isinstance(parsed, dict) and "answer" in parsed:
                    return parsed
            except (json.JSONDecodeError, TypeError):
                pass

    return data


def invoke_runtime(
    client,
    arn: str,
    prompt: str,
    session_id: str,
    actor_id: str,
    debug: bool = False,
    runtime_session_id: str | None = None,
) -> tuple[dict, str]:
    """Invoke the AgentCore runtime and return (parsed_result, runtimeSessionId)."""
    payload: dict = {
        "prompt": prompt,
        "session_id": session_id,
        "actor_id": actor_id,
    }

    kwargs: dict = {
        "agentRuntimeArn": arn,
        "payload": json.dumps(payload),
    }
    if runtime_session_id:
        kwargs["runtimeSessionId"] = runtime_session_id

    response = client.invoke_agent_runtime(**kwargs)

    returned_session_id = response.get("runtimeSessionId", "")

    if debug:
        print(dim(f"  [debug] response keys: {list(response.keys())}"))
        for k, v in response.items():
            if k == "ResponseMetadata":
                continue
            print(dim(f"  [debug] {k}: type={type(v).__name__}, repr={repr(v)[:200]}"))

    body = response.get("response", response.get("body", response.get("output", {})))
    raw = _read_body(body, debug=debug)

    if not raw:
        return {"answer": "(empty response)", "stop_reason": "error", "tool_calls": []}, returned_session_id

    try:
        data = json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        if debug:
            print(dim("  [debug] JSON parse failed, returning raw text"))
        return {"answer": raw, "stop_reason": "unknown", "tool_calls": []}, returned_session_id

    result = _extract_result(data)

    if debug and result is not data:
        print(dim("  [debug] unwrapped from envelope"))

    return result, returned_session_id


# ---------------------------------------------------------------------------
# Display
# ---------------------------------------------------------------------------

def print_result(result: dict, duration: float) -> None:
    print()
    print(bold("--- Answer ---"))
    print(result.get("answer", "(no answer)"))
    print()

    tools = result.get("tool_calls", [])
    if tools:
        print(dim(f"  Tools called: {len(tools)}"))
        for tc in tools:
            print(dim(f"    {tc['tool']}({tc['args']})"))

    mem = result.get("memory", {})
    if mem.get("enabled"):
        restored = mem.get("restored_messages", 0)
        parts = [f"Memory: {green('on')}"]
        if restored:
            parts.append(f"restored {restored} msgs")
        print(dim(f"  {' | '.join(parts)}"))

    print(dim(f"  Duration: {duration:.1f}s | Stop: {result.get('stop_reason', '?')}"))
    print()


# ---------------------------------------------------------------------------
# CloudWatch logs
# ---------------------------------------------------------------------------

def _show_logs(boto_session, log_group: str, minutes: int = 5) -> None:
    """Fetch and print recent CloudWatch logs from the runtime."""
    try:
        cw = boto_session.client("logs")
        end = int(time.time() * 1000)
        start = end - (minutes * 60 * 1000)

        resp = cw.filter_log_events(
            logGroupName=log_group,
            startTime=start,
            endTime=end,
            limit=50,
            interleaved=True,
        )
        events = resp.get("events", [])
        if not events:
            print(dim(f"  No logs in the last {minutes} min."))
            return

        for ev in events:
            msg = ev.get("message", "").rstrip()
            print(f"  {msg}")

        print(dim(f"  ({len(events)} events)"))
    except Exception as exc:
        print(red(f"  {type(exc).__name__}: {exc}"))


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description="AgentCore Demo Remote CLI")
    parser.add_argument(
        "--arn",
        default=os.getenv("AGENTCORE_RUNTIME_ARN"),
        help="AgentCore runtime ARN (or set AGENTCORE_RUNTIME_ARN env var)",
    )
    parser.add_argument(
        "--log-group",
        default=os.getenv(
            "AGENTCORE_LOG_GROUP",
            "/aws/bedrock-agentcore/runtimes/agentcore-bootstrapper-app-logs",
        ),
        help="CloudWatch log group name",
    )
    parser.add_argument(
        "-q", "--query",
        default=None,
        help="Single query (non-interactive)",
    )
    parser.add_argument(
        "--session-id",
        default=None,
        help="Explicit session ID (auto-generated if omitted)",
    )
    parser.add_argument(
        "--actor-id",
        default="cli-remote",
        help="Actor ID (default: cli-remote)",
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Print raw response for debugging",
    )
    args = parser.parse_args()

    if not args.arn:
        print(red("  Error: No runtime ARN. Pass --arn or set AGENTCORE_RUNTIME_ARN in .env"))
        return 1

    session = boto3.Session()
    client = session.client(
        "bedrock-agentcore",
        config=BotoConfig(read_timeout=120, connect_timeout=10),
    )

    session_id = args.session_id or str(_uuid.uuid4())
    actor_id = args.actor_id
    debug = args.debug

    # Single query mode
    if args.query:
        print(dim(f"  Session: {session_id[:8]}  Actor: {actor_id}"))
        print(dim("  Invoking runtime..."))
        start = time.monotonic()
        try:
            result, _ = invoke_runtime(client, args.arn, args.query, session_id, actor_id, debug=debug)
        except Exception as exc:
            print(red(f"  Error: {type(exc).__name__}: {exc}"))
            return 1
        print_result(result, time.monotonic() - start)
        return 0

    # Interactive REPL
    print()
    print(bold("=" * 60))
    print(bold("  AgentCore Demo Remote CLI"))
    print(bold("=" * 60))
    print(f"  Runtime:  {dim(args.arn.split('/')[-1])}")
    print(f"  Session:  {dim(session_id[:8])}")
    print(f"  Actor:    {dim(actor_id)}")
    print()
    print(dim("  Commands:"))
    print(dim("    :session        -- show current session ID"))
    print(dim("    :memory         -- show memory/session details"))
    print(dim("    :new            -- start new session (new session_id)"))
    print(dim("    :logs [min]     -- show recent CloudWatch logs (default 5 min)"))
    print(dim("    :debug          -- toggle debug output"))
    print(dim("    :quit / :q      -- exit"))
    print(bold("=" * 60))
    print()

    runtime_session_id: str | None = None
    last_memory_info: dict | None = None

    while True:
        try:
            user_input = input(f"{cyan('demo')}:{yellow('remote')}> ").strip()
        except (KeyboardInterrupt, EOFError):
            print(dim("\n  Bye."))
            return 0

        if not user_input:
            continue

        if user_input in (":quit", ":q", ":exit"):
            print(dim("  Bye."))
            return 0

        if user_input == ":session":
            print(f"  Session: {session_id}")
            continue

        if user_input == ":memory":
            print(f"  Session ID:          {session_id}")
            print(f"  Actor ID:            {actor_id}")
            print(f"  Runtime Session ID:  {runtime_session_id or '(not yet assigned)'}")
            if last_memory_info:
                enabled = last_memory_info.get("enabled", False)
                restored = last_memory_info.get("restored_messages", 0)
                print(f"  Memory enabled:      {enabled}")
                print(f"  Restored messages:   {restored}")
            else:
                print(dim("  (no memory info yet -- send a query first)"))
            continue

        if user_input == ":new":
            session_id = str(_uuid.uuid4())
            runtime_session_id = None
            print(green(f"  New session: {session_id[:8]}"))
            continue

        if user_input == ":debug":
            debug = not debug
            print(green(f"  Debug: {'on' if debug else 'off'}"))
            continue

        if user_input.startswith(":logs"):
            parts = user_input.split()
            minutes = int(parts[1]) if len(parts) > 1 else 5
            _show_logs(session, args.log_group, minutes)
            continue

        if user_input.startswith(":"):
            print(dim(f"  Unknown command: {user_input}"))
            continue

        print(dim("  Invoking runtime..."))
        start = time.monotonic()
        try:
            result, returned_sid = invoke_runtime(
                client, args.arn, user_input, session_id, actor_id,
                debug=debug, runtime_session_id=runtime_session_id,
            )
        except Exception as exc:
            print(red(f"  {type(exc).__name__}: {exc}"))
            continue

        if returned_sid:
            runtime_session_id = returned_sid

        last_memory_info = result.get("memory")

        print_result(result, time.monotonic() - start)

    return 0


if __name__ == "__main__":
    sys.exit(main())
