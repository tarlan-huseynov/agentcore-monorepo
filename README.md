# Infrastructure Bootstrapper Agent

An AI agent that creates, modifies, and manages real AWS infrastructure via CloudFormation from natural language — built with [Strands Agents SDK](https://strandsagents.com) and deployed to [Amazon Bedrock AgentCore](https://docs.aws.amazon.com/bedrock/latest/userguide/agentcore.html).

> *"I need a REST API with DynamoDB"* → agent generates a CF template → deploys it → monitors until complete → shows the endpoint.
> *"Add a cache layer"* → retrieves existing template → modifies it → deploys via change set → shows diff.

## Architecture

```
User Query ("Create a DynamoDB table for user sessions")
     |
     v
[DemoOrchestrator]                  app/orchestrator.py
     |
     v
[Strands Agent Loop]                strands.Agent (Claude on Bedrock)
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
     v
Answer + Tool Call Log
```

**Infrastructure (Terraform-managed):**

```
terraform/
├── s3.tf          Build trigger → S3 bucket + ZIP upload
├── iam.tf         Execution role (Bedrock, CloudFormation, resource creation, Memory)
├── agentcore.tf   Agent Runtime (code, env vars, protocol)
├── memory.tf      Memory resource + summarization strategy
├── logging.tf     CloudWatch log group
└── outputs.tf     Runtime ID, invoke command
```

## Tools

### Infrastructure Management — `app/cf_tools.py`

| Tool | Purpose | Key Details |
|------|---------|-------------|
| `list_stacks` | Discover deployed stacks | Filter by agent-created tag or show all |
| `describe_stack` | Full stack details | Status, parameters, outputs, resources, events |
| `get_template` | Retrieve current CF template JSON | Use before modifying existing stacks |
| `create_stack` | Deploy new infrastructure | Auto-validates, tags `ManagedBy=agentcore-bootstrapper`, `OnFailure=DELETE` |
| `create_change_set` | Preview changes to existing stack | Polls until ready (3s interval, 60s max), shows diff |
| `execute_change_set` | Apply a previewed change set | Only after review |
| `delete_stack` | Tear down infrastructure | Safety guard: refuses stacks without agent tag |
| `stack_events` | Monitor deployment progress | Diagnose failures, watch CREATE/UPDATE progress |

**Safety guards:**
- All stacks tagged `ManagedBy=agentcore-bootstrapper` + `CreatedAt=<ISO timestamp>`
- `delete_stack` refuses to delete stacks without the agent tag
- Templates validated before deployment; size checked against 51,200 byte limit
- Change sets required for modifications (no direct updates)
- IAM roles in templates must start with `agentcore-cf-` (permission boundary)
- `CAPABILITY_IAM` + `CAPABILITY_NAMED_IAM` passed automatically

### Account Inspection — `app/tools.py`

| Tool | Purpose | Key Details |
|------|---------|-------------|
| `describe_account` | List resources in a region | EC2, Lambda, S3, RDS, DynamoDB, ECS, CloudWatch alarms |
| `get_spending` | Cost breakdown by service | Cost Explorer, 1-90 days, daily or monthly granularity |
| `search_logs` | Search CloudWatch Logs | Pass empty `log_group` to list available groups |

## Prerequisites

- **AWS account** with Bedrock model access enabled (Claude Sonnet 4.5)
- **[uv](https://docs.astral.sh/uv/)** — Python package manager
- **Terraform** >= 1.5
- **AWS CLI** configured with a profile or credentials

## Quick Start

### 1. Local Development

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
demo> Create a DynamoDB table called users with id as partition key

--- Answer ---
I'll create a CloudFormation stack with a DynamoDB table for you.

[Shows CF template JSON, deploys, returns stack ID]

  Tools called: 1
    create_stack({"region": "eu-central-1", "stack_name": "users-table"})
  Duration: 4.2s | Stop: end_turn

demo> Show me the stack events

--- Answer ---
Stack Events for 'users-table' (latest 5):
  [14:32:01] UsersTable (AWS::DynamoDB::Table): CREATE_COMPLETE
  [14:31:45] UsersTable (AWS::DynamoDB::Table): CREATE_IN_PROGRESS
  ...

demo> Add a TTL attribute to the users table

--- Answer ---
I'll retrieve the current template and create a change set...

[Shows proposed changes, waits for approval]

demo> Delete the users stack

--- Answer ---
Stack 'users-table' deletion initiated.
Status: DELETE_IN_PROGRESS
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
- Build the deployment ZIP (ARM64 cross-compiled)
- Create an S3 bucket and upload the ZIP
- Create the IAM execution role (Bedrock + CloudFormation + resource creation)
- Create the AgentCore Memory resource
- Deploy the Agent Runtime

### 3. Test the Deployed Agent

Copy the `invoke_command` from Terraform outputs:

```bash
terraform output -raw invoke_command | bash
```

## Project Structure

```
agentcore-demo/
├── app/                         Python application
│   ├── entrypoint.py            AgentCore Runtime entry point (deferred imports)
│   ├── config.py                Dual-mode config (local/AgentCore)
│   ├── orchestrator.py          Strands agent wrapper + memory integration
│   ├── cf_tools.py              CloudFormation tools (8): create, modify, delete, monitor
│   ├── tools.py                 Account inspection tools (3): resources, costs, logs
│   └── bedrock.py               BedrockModel factory with prompt caching
├── cli.py                       Interactive REPL for local development
├── scripts/package.sh           ARM64 deployment packaging
├── terraform/                   Infrastructure as code
│   ├── main.tf                  Provider + data sources
│   ├── variables.tf             Input variables
│   ├── s3.tf                    Build + upload
│   ├── iam.tf                   Execution role + policies
│   ├── agentcore.tf             Agent Runtime resource
│   ├── memory.tf                Memory + summarization
│   ├── logging.tf               CloudWatch log group
│   └── outputs.tf               Useful outputs
├── pyproject.toml               Dependencies (uv)
└── README.md
```

## How Code Redeployment Works

When you change a Python file and run `terraform apply`:

1. `null_resource.build` detects the source hash changed → re-runs `package.sh`
2. `aws_s3_object` detects new build → re-uploads ZIP to S3
3. `aws_bedrockagentcore_agent_runtime` detects `_CODE_VERSION` env var changed → updates runtime
4. AgentCore re-fetches code from S3 and restarts

The `_CODE_VERSION` env var trick is necessary because AgentCore caches S3 code
at deploy time. Simply updating the S3 object won't trigger a redeploy.

## IAM Permissions

The agent's IAM role includes:

| Category | Scope | Purpose |
|----------|-------|---------|
| ReadOnlyAccess | AWS managed policy | All Describe/List/Get for inspection tools |
| CloudFormation | `*` | Stack CRUD, change sets, validation, tagging |
| IAM | `agentcore-cf-*` roles only | Create/manage roles for CF-created resources |
| Resource creation | `*` | DynamoDB, Lambda, API Gateway, S3, SQS, SNS, CloudWatch, EC2 security groups, Step Functions, EventBridge |
| Bedrock | Claude models | LLM inference |
| AgentCore Memory | Memory resource | Session persistence |
| CloudWatch Logs | AgentCore log groups | Runtime logging |

## Design Principles

- **Strands Agent as orchestrator** — agentic loop handled entirely by the SDK
- **Pure helpers + @tool wrappers** — business logic separated from framework plumbing for testability
- **CloudFormation as source of truth** — no S3 template storage; `get_template()` + `list_stacks()` retrieve state
- **Change sets for modifications** — always preview before applying
- **Agent tag safety** — only delete what the agent created
- **Deferred imports** — heavy deps imported at first invocation (30s AgentCore init timeout)
- **Memory graceful degradation** — agent works without memory if init fails
- **Stateless per query** — fresh agent instance, no carryover

## Clean Up

```bash
cd terraform
terraform destroy
```

This removes all Terraform-managed resources including the S3 bucket (`force_destroy = true`).

**Note:** CloudFormation stacks created by the agent are *not* managed by Terraform. Delete them separately using the agent (`delete_stack`) or the AWS Console.
