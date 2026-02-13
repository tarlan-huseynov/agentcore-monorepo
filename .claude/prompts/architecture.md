# Architecture

## Overview

AgentCore Demo is a minimal Strands Agents application deployed to Amazon
Bedrock AgentCore. It demonstrates the full deployment lifecycle -- from
local development to production -- with three simple tools.

```
User Query
     |
     v
[DemoOrchestrator]          app/orchestrator.py
     |
     v
[Strands Agent Loop]        strands.Agent (Bedrock-powered)
  |          |          |
get_weather get_time  tell_joke    app/tools.py
  |          |          |
Hardcoded   Python     Hardcoded
data        datetime   jokes
     |
     v
Answer + Tool Call Log
```

---

## Key Components

### 1. Orchestrator (`app/orchestrator.py`)

`DemoOrchestrator` is the single entry point. Per query it:

1. Creates an `AgentCoreMemorySessionManager` (if memory is enabled).
2. Creates a fresh `strands.Agent` with three tools and a `BedrockModel`.
3. Runs the agent loop and collects results.
4. Returns `{"answer", "stop_reason", "tool_calls", "memory"}`.

A fresh agent is created per query to prevent state leakage.

### 2. Tools (`app/tools.py`)

Three `@tool(context=True)` functions:
- `get_weather(city)` -- hardcoded weather data for 8 cities
- `get_time(timezone_name)` -- Python `datetime` with timezone offsets
- `tell_joke(topic)` -- random joke from categories

Each tool has a **pure helper** (`_get_weather`, `_get_time`, `_get_joke`)
for direct unit testing, and a `@tool` wrapper that adds invocation_state
tracking.

### 3. Bedrock Client (`app/bedrock.py`)

Factory function `create_model()` returning a `strands.models.BedrockModel`
with prompt caching enabled.

### 4. Config (`app/config.py`)

Dual-mode config:
- **Local:** AWS profile from `.env`, memory disabled by default
- **AgentCore:** IAM role (automatic), memory ID from env vars set by Terraform

### 5. Entrypoint (`app/entrypoint.py`)

`BedrockAgentCoreApp` with deferred heavy imports to stay within the
30-second AgentCore init timeout.

---

## Infrastructure (`terraform/`)

Single `terraform apply` handles the full deployment:

1. `null_resource.build` runs `scripts/package.sh` (ARM64 cross-compile)
2. `aws_s3_object` uploads ZIP to S3
3. `aws_bedrockagentcore_agent_runtime` creates/updates the runtime
4. `aws_bedrockagentcore_memory` + strategy for session persistence
5. `aws_cloudwatch_log_group` for logging

Code redeployment uses a `_CODE_VERSION` env var trick -- changing the
env var forces AgentCore to re-fetch code from S3.

---

## Design Principles

- **Strands Agent as orchestrator:** The agentic loop is handled entirely
  by the Strands Agent SDK. No custom loop logic.
- **Pure helpers + @tool wrappers:** Separating business logic from framework
  plumbing makes tools independently testable.
- **Deferred imports:** Heavy deps (strands, boto3, pydantic) are imported
  at first invocation, not module load, to respect AgentCore's 30s init.
- **Memory graceful degradation:** If memory init fails, the agent proceeds
  without it. If memory corrupts the conversation, retry without memory.
- **Stateless per query:** Fresh agent instance, no carryover.
- **Terraform-managed infra:** Declarative, idempotent, single-command deploy.
