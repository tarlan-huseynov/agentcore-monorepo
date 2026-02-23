# AgentCore Demo - Development Guide

## What This Is

An **Infrastructure Bootstrapper Agent** on Amazon Bedrock AgentCore that creates,
modifies, and manages real AWS infrastructure from natural language:
- **Strands Agents SDK** as the orchestrator (agentic loop)
- **Amazon Bedrock** for LLM inference (Claude models)
- **AgentCore Gateway + MCP Servers** for infrastructure and cost tooling
- **Cloud Control API** (1100+ resource types) via CCAPI MCP Server
- **AgentCore Memory** for multi-turn session persistence
- **Terraform** for single-command deployment

## What This Is NOT

- Not a production infrastructure tool -- demo/reference implementation
- Not a security-critical system -- scoped IAM permissions, agent-tag safety guards
- Designed as a **reference implementation** for AgentCore deployment patterns

## Architecture

```
User Query ("I need a REST API with DynamoDB")
     |
[Agent Runtime]                  app/orchestrator.py (Strands Agent)
  |                    |
  | MCPClient          | Direct @tool
  | (Gateway)          | (Strands)
  |                    |
  v                    v
[AgentCore Gateway]    search_logs (CloudWatch Logs)
  |              |
  v              v
[CCAPI MCP]    [Cost Explorer MCP]
(Runtime 2)    (Runtime 3)
  |              |
  v              v
Cloud Control   Cost Explorer
API (1100+)     API
```

For detailed architecture, see `@.claude/prompts/architecture.md`.

## Project Structure

- `app/` - Python application
  - `orchestrator.py` - Strands agent wrapper + memory integration
  - `tools.py` - CloudWatch Logs search (1 direct tool) with pure helper + `@tool` wrapper
  - `bedrock.py` - BedrockModel factory with prompt caching
  - `config.py` - Dual-mode config (local/AgentCore)
  - `entrypoint.py` - AgentCore Runtime entry point (deferred imports)
- `mcp_servers/` - MCP server entry points
  - `ccapi_entrypoint.py` - CCAPI MCP Server (Cloud Control API, 14 tools)
  - `cost_entrypoint.py` - Cost Explorer MCP Server (7 tools)
- `cli.py` - Interactive REPL for local development
- `scripts/package.sh` - ARM64 deployment packaging
- `terraform/` - Infrastructure as code
  - `gateway.tf` - AgentCore Gateway
  - `mcp_runtimes.tf` - MCP Server Runtimes (CCAPI + Cost Explorer)
  - `gateway_iam.tf` - Gateway + MCP IAM roles
  - (plus S3, IAM, main Runtime, Memory, Logging)

## Key Constraints

1. **Bedrock-only**: All LLM calls via `strands.models.BedrockModel`
2. **Deferred imports**: Heavy deps imported at first invocation (30s AgentCore init timeout)
3. **Pure helpers**: Business logic separated from `@tool` wrappers for testability
4. **Memory graceful degradation**: Agent works without memory if init fails

## Development Workflow

```bash
# Install dependencies
uv sync

# Run locally
uv run python cli.py

# Run tests
uv run pytest tests/ -v

# Lint
uv run ruff check app/ tests/
```

## Deployment

```bash
# Set AWS_PROFILE and AWS_REGION if needed:
#   export AWS_PROFILE=your-profile-name
#   export AWS_REGION=us-east-1

cd terraform
terraform init
terraform apply    # builds + uploads + deploys in one command
```

## Detailed Documentation

@.claude/prompts/system.md
@.claude/prompts/architecture.md
@.claude/rules/agents-and-skills.md

## Gotchas

- `BedrockModel(region_name=..., boto_session=...)` raises ValueError -- use only one
- Newer Bedrock models require inference profile IDs (e.g. `us.anthropic.claude-...`)
- AgentCore 30s init timeout -- heavy imports must be deferred to invoke phase
- AgentCore Memory sessionId/actorId must match `[a-zA-Z0-9][a-zA-Z0-9-_]*` -- use `_sanitize_memory_id()`
- Bedrock Converse API: every `toolResult` must have matching `toolUse` -- memory can break this
- `_CODE_VERSION` env var trick needed to force AgentCore redeploy on S3 code changes
- CCAPI MCP server object: `from awslabs.ccapi_mcp_server.server import mcp`
- Cost Explorer MCP server object: `from awslabs.cost_explorer_mcp_server.server import app`
- `GATEWAY_URL` env var must be set for MCP tools to work (injected by Terraform)
- `mcp` package is already a transitive dep of `strands-agents` -- no separate install needed

## References

- [Strands Agents docs](https://strandsagents.com/latest/documentation/docs/)
- [Bedrock AgentCore docs](https://docs.aws.amazon.com/bedrock/latest/userguide/agentcore.html)
- [Bedrock Converse API](https://docs.aws.amazon.com/bedrock/latest/userguide/conversation-inference.html)
