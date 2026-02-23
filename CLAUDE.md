# AgentCore Demo - Development Guide

## What This Is

An **Infrastructure Bootstrapper Agent** on Amazon Bedrock AgentCore that creates,
modifies, and manages real AWS infrastructure via CloudFormation from natural language:
- **Strands Agents SDK** as the orchestrator (agentic loop)
- **Amazon Bedrock** for LLM inference (Claude models)
- **CloudFormation** for infrastructure creation and management
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
[DemoOrchestrator]                  app/orchestrator.py
     |
[Strands Agent Loop]                strands.Agent (Bedrock-powered)
  |                    |
  |  CF Management     |  Account Inspection
  |  (app/cf_tools.py) |  (app/tools.py)
  |                    |
  |- list_stacks       |- describe_account
  |- describe_stack    |- get_spending
  |- get_template      |- search_logs
  |- create_stack      |
  |- create_change_set |
  |- execute_change_set|
  |- delete_stack      |
  |- stack_events      |
  |                    |
CloudFormation       EC2/Lambda/S3/
API                  Cost Explorer/
                     CloudWatch
     |
Answer + Tool Call Log
```

For detailed architecture, see `@.claude/prompts/architecture.md`.

## Project Structure

- `app/` - Python application
  - `orchestrator.py` - Strands agent wrapper + memory integration
  - `cf_tools.py` - CloudFormation tools (8) with pure helpers + `@tool` wrappers
  - `tools.py` - AWS inspection tools (3) with pure helpers + `@tool` wrappers
  - `bedrock.py` - BedrockModel factory with prompt caching
  - `config.py` - Dual-mode config (local/AgentCore)
  - `entrypoint.py` - AgentCore Runtime entry point (deferred imports)
- `cli.py` - Interactive REPL for local development
- `scripts/package.sh` - ARM64 deployment packaging
- `terraform/` - Infrastructure as code (S3, IAM, Runtime, Memory, Logging)

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

## Gotchas

- `BedrockModel(region_name=..., boto_session=...)` raises ValueError -- use only one
- Newer Bedrock models require inference profile IDs (e.g. `us.anthropic.claude-...`)
- AgentCore 30s init timeout -- heavy imports must be deferred to invoke phase
- AgentCore Memory sessionId/actorId must match `[a-zA-Z0-9][a-zA-Z0-9-_]*` -- use `_sanitize_memory_id()`
- Bedrock Converse API: every `toolResult` must have matching `toolUse` -- memory can break this
- `_CODE_VERSION` env var trick needed to force AgentCore redeploy on S3 code changes
- CF template body max 51,200 bytes -- use S3 for larger templates
- IAM roles in CF templates must start with `agentcore-cf-` (permission boundary)
- All agent-created stacks tagged `ManagedBy=agentcore-bootstrapper` -- delete_stack refuses untagged stacks

## References

- [Strands Agents docs](https://strandsagents.com/latest/documentation/docs/)
- [Bedrock AgentCore docs](https://docs.aws.amazon.com/bedrock/latest/userguide/agentcore.html)
- [Bedrock Converse API](https://docs.aws.amazon.com/bedrock/latest/userguide/conversation-inference.html)
