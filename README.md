# Infrastructure Bootstrapper Agent

An AI agent that creates, modifies, and manages real AWS infrastructure from natural language — built with [Strands Agents SDK](https://strandsagents.com) and deployed to [Amazon Bedrock AgentCore](https://docs.aws.amazon.com/bedrock/latest/userguide/agentcore.html). This reference implementation showcases nearly every AgentCore pillar — **Runtime, Memory, Gateway, MCP, and Policy** — in one demo: the agent reaches 22 tools through a single Gateway endpoint backed by two purpose-built MCP servers, with Cedar policies enforcing safety guardrails.

> *"Create a DynamoDB table for user sessions"* → agent calls CCAPI MCP → resource created → returns ARN.
> *"What did we spend on Lambda last month?"* → agent calls Cost Explorer MCP → breakdown returned.

## Architecture

```
User Query
     |
     v
[DemoOrchestrator]                          app/orchestrator.py
     |
     v
[Strands Agent Loop]                        strands.Agent (Claude on Bedrock)
     |                         |
     |  Gateway MCP tools      |  Direct tool
     |  (22 via Gateway)       |  (app/tools.py)
     |                         |
     v                         v
[AgentCore Gateway]        search_logs
     |  (Cedar Policy)
     +---------------------------+
     |                           |
     v                           v
[CCAPI MCP Server]      [Cost Explorer MCP Server]
 14 tools                7 tools
 Cloud Control API       AWS Cost Explorer
     |                           |
     v                           v
AWS Resources            Billing + Forecasts
(1100+ resource types)
```

**Infrastructure (Terraform-managed):**

```
terraform/
├── main.tf            Provider + data sources + locals
├── variables.tf       Input variables
├── s3.tf              Build triggers + S3 bucket + 3 ZIP uploads
├── iam.tf             Agent Runtime role (Bedrock + Memory + ReadOnly)
├── agentcore.tf       Agent Runtime (HTTP, 1 runtime)
├── memory.tf          Memory resource + summarization strategy
├── logging.tf         CloudWatch log group
├── gateway.tf         AgentCore Gateway + Targets (CLI-managed via setup_targets.sh)
├── mcp_runtimes.tf    CCAPI + Cost Explorer MCP Runtimes (MCP protocol)
├── cognito.tf         Cognito User Pool + OAuth2 credential provider (M2M auth)
├── gateway_iam.tf     Gateway role + CCAPI MCP role + Cost MCP role
├── policy.tf          Cedar policy engine setup (via AWS CLI)
├── policies/          Cedar policy files
│   └── safety.cedar   Safety guardrails (resource type restrictions)
└── outputs.tf         Runtime IDs, Gateway URL, invoke command
```

## Authentication (Cognito OAuth)

The Gateway authenticates to MCP server runtimes using **Cognito M2M (machine-to-machine) OAuth**. No human users are involved — no sign-up, no passwords, no user pool management needed.

```
Gateway                     Cognito                     MCP Runtime
   |                           |                            |
   |-- client_credentials ---->|                            |
   |   (client_id + secret)    |                            |
   |<---- Bearer token --------|                            |
   |                                                        |
   |-- tools/call + Bearer ---------------------------------|
   |                                   validates JWT (JWKS) |
   |<-------------- tool result ----------------------------|
```

**Why Cognito?** AgentCore MCP runtimes reject SigV4 for MCP protocol (HTTP 406). OAuth is the only supported auth method for Gateway-to-Runtime communication. Cognito acts purely as a token issuer.

**What Terraform creates:**
- `aws_cognito_user_pool` — OIDC token authority (no actual users)
- `aws_cognito_resource_server` — defines `mcp/invoke` scope
- `aws_cognito_user_pool_client` — M2M client (`client_credentials` grant only)
- `aws_bedrockagentcore_oauth2_credential_provider` — tells the Gateway where to get tokens

All of this is fully automated by `terraform apply`. No manual Cognito configuration needed.

## Safety Guardrails (Cedar Policy + IAM)

Safety is enforced at two layers:

**1. Cedar Policy Engine** — attached to the Gateway, evaluates every MCP tool call against Cedar rules:

| Rule | What it does |
|------|-------------|
| **Read-only tools: always allowed** | `list_resources`, `get_resource`, `explain`, `run_checkov`, all Cost Explorer tools — no restrictions |
| **Create/update: resource type allowlist** | Only DynamoDB, S3, SQS, SNS, Lambda, EventBridge, CloudWatch, API Gateway, Step Functions, Log Groups |
| **Delete: restricted allowlist** | Only DynamoDB, SQS, SNS, CloudWatch Alarms, Log Groups — cannot delete S3 buckets, Lambda functions, etc. |
| **Default deny** | Any tool/action not explicitly permitted is blocked |

Policy is defined in `terraform/policies/safety.cedar`. Currently runs in `LOG_ONLY` mode (see [Tech Debt](#tech-debt) for why).

**2. Scoped IAM roles** — each MCP server runtime has minimal IAM permissions. Even if Cedar doesn't block a tool call, the runtime's IAM role must have the underlying AWS permission. For example, the CCAPI role has no `ec2:TerminateInstances` — so deleting EC2 instances fails at the IAM layer regardless of Cedar.

## Tools

The agent accesses 22 tools across three sources: 14 from CCAPI MCP Server, 7 from Cost Explorer MCP Server, and 1 direct tool.

### CCAPI MCP Server — `mcp_servers/ccapi_entrypoint.py` (14 tools)

Backed by the [awslabs Cloud Control API MCP Server](https://github.com/awslabs/mcp/tree/main/src/ccapi-mcp-server). Provides CRUDL operations across 1100+ AWS resource types via the Cloud Control API.

| Tool | Purpose |
|------|---------|
| `check_environment_variables` | Verify required env vars are set for the MCP server |
| `get_aws_session_info` | Show current AWS credentials and session metadata |
| `get_aws_account_info` | Account ID, partition, default region |
| `get_resource_schema_information` | CloudFormation type schema for any resource type |
| `list_resources` | List resources of a given type in a region |
| `get_resource` | Get properties of a specific resource by identifier |
| `create_resource` | Create a resource from a properties JSON document |
| `update_resource` | Patch a resource using JSON Patch operations |
| `delete_resource` | Delete a resource by identifier |
| `get_resource_request_status` | Poll async CCAPI operation status |
| `generate_infrastructure_code` | Generate CloudFormation or Terraform from existing resources |
| `explain` | Explain any CloudFormation resource type in plain language |
| `create_template` | Build a multi-resource CloudFormation template |
| `run_checkov` | Run security/compliance scan on a CloudFormation template |

### Cost Explorer MCP Server — `mcp_servers/cost_entrypoint.py` (7 tools)

Backed by the [awslabs Cost Explorer MCP Server](https://github.com/awslabs/mcp/tree/main/src/cost-explorer-mcp-server). Read-only access to AWS billing data.

| Tool | Purpose |
|------|---------|
| `get_today_date` | Return today's date (anchor for relative cost queries) |
| `get_cost_and_usage` | Spending breakdown by service, tag, or linked account |
| `get_cost_forecast` | Projected spend for a future date range |
| `get_dimension_values` | Valid values for a Cost Explorer dimension (services, regions, etc.) |
| `get_tag_values` | All values for a given cost allocation tag key |
| `get_cost_and_usage_comparisons` | Side-by-side comparison across two time periods |
| `get_cost_comparison_drivers` | Identify what drove a cost change between periods |

### Direct Tool — `app/tools.py` (1 tool)

| Tool | Purpose | Key Details |
|------|---------|-------------|
| `search_logs` | Search CloudWatch Logs | Pass empty `log_group` to list available groups; can read the agent's own runtime logs |

## Prerequisites

- **AWS account** with Bedrock model access enabled (Claude Sonnet 4.6)
- **[uv](https://docs.astral.sh/uv/)** — Python package manager
- **Terraform** >= 1.5 with AWS provider >= 6.21 (required for `aws_bedrockagentcore_gateway` and MCP target resources)
- **AWS CLI** >= 2.31.13 configured with a profile or credentials

## Quick Start

### 1. Local Development

> **Note:** Local mode runs without the AgentCore Gateway. The Strands agent uses only the `search_logs` direct tool. The 21 MCP-backed tools are available only when deployed.

```bash
git clone <repo-url>
cd agentcore-demo
uv sync

# Configure
cp .env.example .env
# Edit .env: set AWS_PROFILE to your profile name

# Run the CLI
uv run python cli.py
```

```
demo> What CloudWatch log groups are available?

--- Answer ---
Available log groups in eu-central-1:
  /aws/bedrock-agentcore/runtimes/...
  /aws/lambda/my-function
  ...

  Tools called: 1
    search_logs({"log_group": "", "region": "eu-central-1"})
  Duration: 1.8s | Stop: end_turn

demo> Search the agent's logs for errors in the last 30 minutes

--- Answer ---
Found 3 entries matching "ERROR" ...
```

### 2. Deploy to AgentCore

```bash
# Set AWS_PROFILE and AWS_REGION if needed:
#   export AWS_PROFILE=your-profile-name
#   export AWS_REGION=us-east-1

cd terraform
terraform init
terraform apply
```

Terraform will:
- Build 3 deployment ZIPs (agent, CCAPI MCP server, Cost Explorer MCP server)
- Create an S3 bucket and upload all 3 ZIPs
- Create IAM roles for the agent runtime, Gateway, CCAPI MCP server, and Cost MCP server
- Deploy 2 MCP server Runtimes (MCP protocol)
- Create the AgentCore Gateway with 2 targets pointing at the MCP runtimes
- Create the AgentCore Memory resource
- Deploy the Agent Runtime (HTTP protocol) with the Gateway URL injected as `GATEWAY_URL`

### 3. Test the Deployed Agent

Copy the `invoke_command` from Terraform outputs:

```bash
terraform output -raw invoke_command | bash
```

Or invoke directly:

```bash
aws bedrock-agentcore invoke-agent-runtime \
  --agent-runtime-arn "<runtime-arn>" \
  --content-type "application/json" \
  --accept "application/json" \
  --payload '{"prompt": "Create an S3 bucket called my-demo-bucket-12345"}' \
  response.json && cat response.json
```

## E2E Tests

```bash
AWS_PROFILE=your-profile bash scripts/test_e2e.sh
```

Runs 16 tests across the full deployed stack (Agent Runtime → LLM → Gateway → Cedar → OAuth → MCP Runtime → AWS API):

| Layer | Tests | What it checks |
|-------|-------|----------------|
| Infrastructure Health | 6 | All 3 runtimes READY, Gateway READY, both targets READY |
| CCAPI MCP Tools | 5 | get_aws_session_info, explain, get_resource_schema_information, list_resources, create_template |
| Cost Explorer MCP Tools | 3 | get_today_date, get_cost_and_usage, get_dimension_values |
| Direct Tool | 1 | search_logs (CloudWatch Logs) |
| Safety Guardrails | 1 | EC2 delete blocked by Cedar + IAM |

## Project Structure

```
agentcore-demo/
├── app/                            Python application (agent runtime)
│   ├── entrypoint.py               AgentCore Runtime entry point (deferred imports)
│   ├── config.py                   Dual-mode config (local/AgentCore)
│   ├── orchestrator.py             Strands agent wrapper + Gateway MCP + memory
│   ├── tools.py                    Direct tool: search_logs
│   └── bedrock.py                  BedrockModel factory with prompt caching
├── mcp_servers/                    MCP server entry points
│   ├── ccapi_entrypoint.py         CCAPI MCP server (streamable-http)
│   └── cost_entrypoint.py          Cost Explorer MCP server (streamable-http)
├── cli.py                          Interactive REPL for local development
├── scripts/
│   ├── package.sh                  ARM64 packaging for the agent runtime
│   ├── package_mcp.sh              ARM64 packaging for both MCP servers
│   ├── setup_targets.sh            Gateway target management (CLI, see Tech Debt)
│   ├── setup_policy.sh             Cedar policy engine setup (CLI, see Tech Debt)
│   └── test_e2e.sh                 E2E test suite (16 tests)
├── terraform/                      Infrastructure as code
│   ├── main.tf                     Provider + data sources + locals
│   ├── variables.tf                Input variables
│   ├── s3.tf                       Build triggers + S3 uploads (3 packages)
│   ├── iam.tf                      Agent Runtime IAM role
│   ├── agentcore.tf                Agent Runtime resource (HTTP)
│   ├── memory.tf                   Memory + summarization strategy
│   ├── logging.tf                  CloudWatch log group
│   ├── gateway.tf                  Gateway + Targets (CLI-managed)
│   ├── mcp_runtimes.tf             CCAPI + Cost Explorer Runtimes (MCP)
│   ├── cognito.tf                  Cognito User Pool + OAuth2 (M2M auth)
│   ├── gateway_iam.tf              Gateway + MCP server IAM roles
│   └── outputs.tf                  Runtime IDs, Gateway URL, invoke command
├── pyproject.toml                  Dependencies (uv)
└── README.md
```

## How Code Redeployment Works

There are three independently tracked packages. When you change source files and run `terraform apply`:

**Agent runtime** (`app/` changes):
1. `null_resource.build` detects source hash changed → re-runs `scripts/package.sh`
2. `aws_s3_object.deployment_package` detects new build → re-uploads `deployment_package.zip`
3. `aws_bedrockagentcore_agent_runtime.demo` detects `_CODE_VERSION` changed → updates runtime

**CCAPI MCP server** (`mcp_servers/ccapi_entrypoint.py` changes):
1. `null_resource.build_ccapi` detects change → re-runs `scripts/package_mcp.sh`
2. `aws_s3_object.ccapi_package` re-uploads `mcp_ccapi_package.zip`
3. `aws_bedrockagentcore_agent_runtime.ccapi` picks up `_CODE_VERSION` change → redeploys

**Cost Explorer MCP server** (`mcp_servers/cost_entrypoint.py` changes):
1. Same pattern via `null_resource.build_cost` → `mcp_cost_package.zip` → `cost_explorer` runtime

The `_CODE_VERSION` env var trick is necessary because AgentCore caches S3 code at deploy time. Simply updating the S3 object won't trigger a redeploy — changing an env var forces the runtime to re-fetch code from S3.

## IAM Permissions

Four IAM roles are created. Each role is scoped to its exact function.

### Agent Runtime Role (`iam.tf`)

| Category | Scope | Purpose |
|----------|-------|---------|
| ReadOnlyAccess | AWS managed policy | All Describe/List/Get for `search_logs` |
| Bedrock invoke | Claude models | LLM inference |
| AgentCore Memory | Memory resource | Session persistence (CreateEvent, ListEvents, etc.) |
| S3 GetObject | Code bucket | Fetch deployment artifact |
| CloudWatch Logs write | AgentCore log groups | Runtime logging |

### Gateway Role (`gateway_iam.tf`)

| Category | Scope | Purpose |
|----------|-------|---------|
| InvokeAgentRuntime | CCAPI + Cost MCP Runtime ARNs | Route tool calls from Gateway to MCP servers |
| PolicyEngine | `*` | Evaluate Cedar policies (AuthorizeAction, PartiallyAuthorizeActions) |
| OutboundOAuth | `*` | Get Bearer tokens from Cognito (GetWorkloadAccessToken, GetResourceOauth2Token) |
| SecretsManager | `bedrock-agentcore*` | Read Cognito client_secret (stored by credential provider) |
| CloudWatch Logs write | AgentCore gateway log groups | Gateway logging |

### CCAPI MCP Server Role (`gateway_iam.tf`)

| Category | Scope | Purpose |
|----------|-------|---------|
| Cloud Control API | `*` | CRUDL across all resource types |
| CloudFormation schema/IaC | `*` | Schema lookup, template generation |
| Service permissions | `*` | DynamoDB, Lambda, API Gateway, S3, SQS, SNS, CloudWatch, EC2, Step Functions, EventBridge |
| IAM | `agentcore-cf-*` roles only | Create/manage roles for agent-created resources |
| CloudWatch Logs write | AgentCore log groups | Runtime logging |

### Cost Explorer MCP Server Role (`gateway_iam.tf`)

| Category | Scope | Purpose |
|----------|-------|---------|
| Cost Explorer | `ce:GetCostAndUsage`, `ce:GetCostForecast`, etc. | Read-only billing queries |
| CloudWatch Logs write | AgentCore log groups | Runtime logging |

## Design Principles

- **Gateway as tool aggregator** — the agent connects to one MCP endpoint and discovers all 21 Gateway-backed tools; no per-service wiring in the orchestrator
- **MCP as the integration protocol** — both MCP server runtimes speak streamable-http MCP; the Gateway handles auth, routing, and tool namespacing
- **Hybrid tool pattern** — MCP tools for infrastructure work, a direct `@tool` function for log search; mix as appropriate for each use case
- **Purpose-built MCP servers** — CCAPI and Cost Explorer servers run as isolated runtimes with minimal, scoped IAM roles; blast radius is contained
- **Cedar Policy as guardrails** — deterministic safety enforcement at the Gateway level; restricts which resource types the agent can create, update, or delete; no prompt engineering required
- **Strands Agent as orchestrator** — the agentic loop is handled entirely by the SDK, including MCP client management
- **Deferred imports** — heavy deps imported at first invocation to stay within the AgentCore 30s init timeout
- **Memory graceful degradation** — agent works without memory if init fails
- **Stateless per query** — fresh agent instance per invocation, no state carryover

## Tech Debt

Three Terraform workarounds exist because the AWS provider (~6.32) hasn't caught up with the AgentCore API. Each is documented here with the fix that would eliminate it.

### 1. Gateway Targets managed via bash script instead of Terraform

**Problem:** The `aws_bedrockagentcore_gateway_target` resource doesn't support `grantType` on the OAuth credential provider configuration. Without `grantType: CLIENT_CREDENTIALS`, the Gateway can't fetch Bearer tokens from Cognito.

**Workaround:** `scripts/setup_targets.sh` creates/updates targets via AWS CLI. Terraform invokes it via `null_resource.gateway_targets`.

**Fix:** AWS adds `grant_type` attribute to `aws_bedrockagentcore_gateway_target` credential provider block → replace `null_resource` with native `aws_bedrockagentcore_gateway_target` resources.

### 2. Policy Engine managed via bash script instead of Terraform

**Problem:** No Terraform resource exists for `PolicyEngine` or `Policy` in the AgentCore namespace.

**Workaround:** `scripts/setup_policy.sh` creates the policy engine, splits Cedar into per-statement policies (API requirement), scopes each to the Gateway ARN, and attaches the engine to the Gateway via `update-gateway`. Terraform invokes it via `null_resource.policy_setup`.

**Fix:** AWS adds `aws_bedrockagentcore_policy_engine` and `aws_bedrockagentcore_policy` resources → replace `null_resource` + bash with native TF resources.

### 3. Gateway `ignore_changes` lifecycle hack

**Problem:** The TF provider doesn't read back `description` and `protocol_configuration` from the `get-gateway` API. Every `terraform apply` sees drift, updates the Gateway, and the update strips the `policyEngineConfiguration` (which isn't in the TF schema).

**Workaround:** `lifecycle { ignore_changes = [description, protocol_configuration] }` on the gateway resource prevents unnecessary updates that would strip the policy engine.

**Fix:** AWS fixes the provider to correctly read back all gateway attributes → remove the `ignore_changes` block.

### 4. Cedar policy engine runs in LOG_ONLY instead of ENFORCE

**Problem:** `ENFORCE` mode returns "Policy Evaluation Internal Failure" regardless of policy content or IAM permissions. This appears to be a service-level issue (tested in eu-central-1 as of Feb 2025). Policies are ACTIVE and correctly structured but evaluation fails internally.

**Workaround:** Policy engine attached in `LOG_ONLY` mode — Cedar evaluates and logs decisions but doesn't block. Safety enforcement falls back to scoped IAM roles on each MCP server runtime (e.g., CCAPI role has no EC2 instance permissions).

**Fix:** AWS resolves the ENFORCE mode internal failure → change `LOG_ONLY` to `ENFORCE` in `scripts/setup_policy.sh`.

## Clean Up

```bash
cd terraform
terraform destroy
```

This removes all Terraform-managed resources: 3 Runtimes, 1 Gateway, 2 Gateway Targets, Policy Engine, Memory, IAM roles, and the S3 bucket (`force_destroy = true`).

**Note:** Resources created by the agent via CCAPI (DynamoDB tables, Lambda functions, S3 buckets, etc.) are *not* managed by Terraform. Delete them separately using the agent or the AWS Console before running `terraform destroy`.
