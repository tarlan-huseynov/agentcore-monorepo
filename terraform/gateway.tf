# ---------------------------------------------------------------------------
# AgentCore Gateway — single MCP endpoint aggregating CCAPI + Cost Explorer
#
# Authentication flow:
#   Gateway → Runtime: OAuth (Cognito client_credentials Bearer token)
#   Client → Gateway:  NONE (demo; production would use AWS_IAM)
# ---------------------------------------------------------------------------

resource "aws_bedrockagentcore_gateway" "main" {
  name            = "${local.name}-gateway"
  description     = "MCP Gateway: CCAPI + Cost Explorer tools"
  role_arn        = aws_iam_role.gateway.arn
  protocol_type   = "MCP"
  authorizer_type = "NONE"

  protocol_configuration {
    mcp {
      instructions       = "Gateway for infrastructure management and cost analysis"
      supported_versions = ["2025-03-26"]
    }
  }

  tags = { Project = var.project_name }

  # The TF provider doesn't properly read back description and
  # protocol_configuration from the API, so they always show as drift.
  # Ignore to prevent unnecessary updates that strip the policy engine.
  lifecycle {
    ignore_changes = [description, protocol_configuration]
  }
}

# ---------------------------------------------------------------------------
# Gateway Targets — each points to an MCP server Runtime
#
# Managed via AWS CLI (scripts/setup_targets.sh) because the Terraform
# provider (~> 6.32) does not support `grantType` on the OAuth credential
# provider configuration — required for the Gateway to fetch Bearer tokens
# using Cognito client_credentials grant.
#
# The script creates/updates targets with:
#   - grantType: CLIENT_CREDENTIALS
#   - ?qualifier=DEFAULT on runtime endpoint URLs
#   - OAuth credential provider for Cognito M2M tokens
# ---------------------------------------------------------------------------

resource "null_resource" "gateway_targets" {
  triggers = {
    # Re-run when runtimes or credential provider change
    ccapi_arn    = aws_bedrockagentcore_agent_runtime.ccapi.agent_runtime_arn
    cost_arn     = aws_bedrockagentcore_agent_runtime.cost_explorer.agent_runtime_arn
    cred_provider = aws_bedrockagentcore_oauth2_credential_provider.gateway_m2m.credential_provider_arn
    script_hash  = filesha256("${path.module}/../scripts/setup_targets.sh")
  }

  provisioner "local-exec" {
    command     = "bash scripts/setup_targets.sh"
    working_dir = "${path.module}/.."

    environment = {
      GATEWAY_ID              = aws_bedrockagentcore_gateway.main.gateway_id
      CCAPI_RUNTIME_ARN       = aws_bedrockagentcore_agent_runtime.ccapi.agent_runtime_arn
      COST_RUNTIME_ARN        = aws_bedrockagentcore_agent_runtime.cost_explorer.agent_runtime_arn
      CREDENTIAL_PROVIDER_ARN = aws_bedrockagentcore_oauth2_credential_provider.gateway_m2m.credential_provider_arn
      SCOPES                  = "mcp/invoke"
      REGION                  = local.region
    }
  }

  depends_on = [
    aws_bedrockagentcore_gateway.main,
    aws_iam_role_policy.gateway,
    aws_bedrockagentcore_agent_runtime.ccapi,
    aws_bedrockagentcore_agent_runtime.cost_explorer,
    aws_bedrockagentcore_oauth2_credential_provider.gateway_m2m,
  ]
}
