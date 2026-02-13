#!/usr/bin/env python3
"""Demo CLI -- interactive REPL for local development.

Usage:
    uv run python cli.py                          # interactive mode
    uv run python cli.py -q "Weather in Tokyo?"   # single query
"""

from __future__ import annotations

import argparse
import sys
import time
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from dotenv import load_dotenv

load_dotenv()

from app.orchestrator import DemoOrchestrator  # noqa: E402

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


def red(t: str) -> str:
    return _c("31", t)


def print_result(result: dict, duration: float) -> None:
    print()
    print(bold("--- Answer ---"))
    print(result["answer"])
    print()
    tools = result.get("tool_calls", [])
    if tools:
        print(dim(f"  Tools called: {len(tools)}"))
        for tc in tools:
            print(dim(f"    {tc['tool']}({tc['args']})"))
    mem = result.get("memory", {})
    if mem.get("enabled"):
        print(dim(f"  Memory: enabled (session={mem['session_id'][:8]}...)"))
    print(dim(f"  Duration: {duration:.1f}s | Stop: {result['stop_reason']}"))
    print()


def main() -> int:
    parser = argparse.ArgumentParser(description="AgentCore Demo CLI")
    parser.add_argument("-q", "--query", help="Single query (non-interactive)")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()

    if args.verbose:
        import logging

        logging.basicConfig(level=logging.DEBUG)

    print(dim("  Initializing Bedrock model..."))
    try:
        orchestrator = DemoOrchestrator()
    except Exception as exc:
        print(red(f"  Init failed: {exc}"))
        return 1
    print(green("  Ready."))

    session_id = str(uuid.uuid4())
    actor_id = "cli-local"

    if args.query:
        start = time.monotonic()
        result = orchestrator.ask(args.query, session_id, actor_id)
        print_result(result, time.monotonic() - start)
        return 0

    print()
    print(bold("=" * 50))
    print(bold("  AgentCore Demo CLI"))
    print(bold("=" * 50))
    print(dim("  Tools: get_weather, get_time, tell_joke"))
    print(dim("  Type :quit to exit"))
    print(bold("=" * 50))
    print()

    while True:
        try:
            user_input = input(f"{cyan('demo')}> ").strip()
        except (KeyboardInterrupt, EOFError):
            print(dim("\n  Bye."))
            return 0

        if not user_input:
            continue
        if user_input in (":quit", ":q", ":exit"):
            print(dim("  Bye."))
            return 0

        start = time.monotonic()
        try:
            result = orchestrator.ask(user_input, session_id, actor_id)
        except Exception as exc:
            print(red(f"  Error: {exc}"))
            continue
        print_result(result, time.monotonic() - start)

    return 0


if __name__ == "__main__":
    sys.exit(main())
