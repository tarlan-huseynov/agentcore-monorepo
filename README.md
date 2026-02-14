# AgentCore Demo

A minimal Strands Agents application deployed to Amazon Bedrock AgentCore using Terraform.

This demo showcases:
- **Strands Agents SDK** orchestrator with `@tool` functions
- **Amazon Bedrock** for LLM inference (Claude models)
- **AgentCore Memory** for multi-turn session persistence
- **Terraform-managed deployment** — single `terraform apply` builds, uploads, and deploys

## Why Terraform for AgentCore?

The AWS CLI's `update-agent-runtime` command treats omitted fields as "clear them."
Every deployment script must:

1. **Read** the current runtime state (`get-agent-runtime`)
2. **Extract** every mutable field (roleArn, networkMode, environmentVariables, etc.)
3. **Pass them all back** to `update-agent-runtime`

Miss one field and it gets wiped. This requires ~130 lines of fragile shell script
(see `deploy.sh` in the ATHENA project for a real example).

**Terraform solves this entirely.** You declare the desired state once in `.tf` files.
Change one field, run `terraform apply`, and only that field changes. Everything else
is preserved in Terraform state.

### Single-command deployment

```bash
terraform apply   # builds code → uploads to S3 → deploys runtime → creates memory
```

This single command:
1. Runs `scripts/package.sh` to build the deployment ZIP (via `null_resource`)
2. Uploads the ZIP to S3 (via `aws_s3_object`)
3. Creates/updates the AgentCore runtime (via `aws_bedrockagentcore_agent_runtime`)
4. Creates the Memory resource + summarization strategy
5. Sets all environment variables, IAM roles, and logging

## Architecture

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

**Infrastructure (managed by Terraform):**

```
terraform/
├── s3.tf          Build trigger → S3 bucket + ZIP upload
├── iam.tf         Execution role (Bedrock, CloudWatch, Memory)
├── agentcore.tf   Agent Runtime (code, env vars, protocol)
├── memory.tf      Memory resource + summarization strategy
├── logging.tf     CloudWatch log group
└── outputs.tf     Runtime ID, invoke command, etc.
```

## Prerequisites

- **AWS account** with Bedrock model access enabled (Claude Sonnet 4.5)
- **[uv](https://docs.astral.sh/uv/)** — Python package manager
- **Terraform** >= 1.5
- **AWS CLI** configured with a profile or credentials

## Quick Start

### 1. Local Development

```bash
# Clone and install
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
demo> What's the weather in Tokyo?

--- Answer ---
The weather in Tokyo is Sunny, 28°C, with 55% humidity.

  Tools called: 1
    get_weather({'city': 'Tokyo'})
  Duration: 2.3s | Stop: end_turn

demo> Tell me a cloud joke

--- Answer ---
Here's one: I told my server a joke. It didn't laugh -- it just returned 200 OK.

  Tools called: 1
    tell_joke({'topic': 'cloud'})
  Duration: 1.8s | Stop: end_turn
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
- Create the IAM execution role
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
│   ├── entrypoint.py            AgentCore Runtime entry point
│   ├── config.py                Dual-mode config (local/agentcore)
│   ├── orchestrator.py          Strands agent wrapper + memory
│   ├── tools.py                 @tool: get_weather, get_time, tell_joke
│   └── bedrock.py               BedrockModel factory
├── cli.py                       Interactive REPL for local dev
├── scripts/package.sh           ARM64 deployment packaging
├── terraform/                   Infrastructure as code
│   ├── main.tf                  Provider + data sources
│   ├── variables.tf             Input variables
│   ├── s3.tf                    Build + upload (the key piece)
│   ├── iam.tf                   Execution role + policy
│   ├── agentcore.tf             Agent Runtime resource
│   ├── memory.tf                Memory + summarization
│   ├── logging.tf               CloudWatch log group
│   └── outputs.tf               Useful outputs
├── pyproject.toml               Dependencies (uv)
└── README.md                    This file
```

## How Code Redeployment Works

When you change a Python file and run `terraform apply`:

1. `null_resource.build` detects the source hash changed → re-runs `package.sh`
2. `aws_s3_object` detects new build → re-uploads ZIP to S3
3. `aws_bedrockagentcore_agent_runtime` detects `_CODE_VERSION` env var changed → updates runtime
4. AgentCore re-fetches code from S3 and restarts

The `_CODE_VERSION` env var trick is necessary because AgentCore caches S3 code
at deploy time. Simply updating the S3 object won't trigger a redeploy — changing
an environment variable forces the runtime to re-fetch.

## Clean Up

```bash
cd terraform
terraform destroy
```

This removes all resources including the S3 bucket (`force_destroy = true`).
