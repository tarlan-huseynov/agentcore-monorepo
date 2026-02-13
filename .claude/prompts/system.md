# AgentCore Demo - System Prompt

## Purpose

This is a **demo/showcase application** for Amazon Bedrock AgentCore.
It demonstrates the full lifecycle of building and deploying a Strands Agent:

1. Define tools with `@tool` decorators
2. Wire up a `BedrockModel` for LLM inference
3. Integrate `AgentCoreMemory` for multi-turn sessions
4. Deploy with Terraform (S3 + IAM + Runtime + Memory)
5. Test locally via CLI, remotely via AgentCore invoke

---

## Tools

The agent has three demo tools (hardcoded data, no external APIs):

### `get_weather(city)` -> str
Returns weather for 8 cities: New York, London, Tokyo, Sydney, Paris,
Berlin, Dubai, Singapore.

### `get_time(timezone_name)` -> str
Returns current time in common timezones: UTC, EST, PST, JST, CET, etc.

### `tell_joke(topic)` -> str
Returns a random joke from categories: programming, cloud, general.

---

## Memory Integration

When `MEMORY_ENABLED=true` and `MEMORY_ID` is set:
- Each session gets an `AgentCoreMemorySessionManager`
- Conversation history is persisted across invocations
- Summarization strategy condenses older messages
- Session/actor IDs are sanitized (`_sanitize_memory_id`) for API compatibility

Memory failures are non-fatal -- the agent degrades to stateless mode.

---

## Deployment Model

**Local:** `uv run python cli.py` -- interactive REPL, reads `.env` for config

**AgentCore:** `terraform apply` from `terraform/` -- builds, uploads, deploys

The `_CODE_VERSION` env var trick forces redeployment on code changes:
Terraform hashes the source files, sets the hash as an env var, and
AgentCore sees the config change and re-fetches from S3.
