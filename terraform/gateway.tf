# ---------------------------------------------------------------------------
# AgentCore Gateway — single MCP endpoint aggregating CCAPI + Cost Explorer
# ---------------------------------------------------------------------------

resource "aws_bedrockagentcore_gateway" "main" {
  name            = "${local.name}-gateway"
  description     = "MCP Gateway: CCAPI + Cost Explorer tools"
  role_arn        = aws_iam_role.gateway.arn
  protocol_type   = "MCP"
  authorizer_type = "NONE" # Demo simplicity; production would use AWS_IAM

  protocol_configuration {
    mcp {
      instructions       = "Gateway for infrastructure management and cost analysis"
      search_type        = "SEMANTIC"
      supported_versions = ["2025-03-26", "2025-06-18"]
    }
  }

  tags = { Project = var.project_name }
}

# ---------------------------------------------------------------------------
# Gateway Targets — each points to an MCP server Runtime
# ---------------------------------------------------------------------------

resource "aws_bedrockagentcore_gateway_target" "ccapi" {
  name               = "ccapi-mcp-server"
  description        = "Cloud Control API — infrastructure CRUDL for 1100+ resource types"
  gateway_identifier = aws_bedrockagentcore_gateway.main.gateway_id

  target_configuration {
    mcp {
      mcp_server {
        endpoint = "https://bedrock-agentcore.${local.region}.amazonaws.com/runtimes/${urlencode(aws_bedrockagentcore_agent_runtime.ccapi.agent_runtime_arn)}/invocations"
      }
    }
  }

  credential_provider_configuration {
    oauth {
      provider_arn = aws_bedrockagentcore_oauth2_credential_provider.gateway_m2m.credential_provider_arn
      scopes       = aws_cognito_resource_server.mcp.scope_identifiers
    }
  }
}

resource "aws_bedrockagentcore_gateway_target" "cost_explorer" {
  name               = "cost-explorer-mcp-server"
  description        = "AWS Cost Explorer — spending analysis and forecasts"
  gateway_identifier = aws_bedrockagentcore_gateway.main.gateway_id

  target_configuration {
    mcp {
      mcp_server {
        endpoint = "https://bedrock-agentcore.${local.region}.amazonaws.com/runtimes/${urlencode(aws_bedrockagentcore_agent_runtime.cost_explorer.agent_runtime_arn)}/invocations"
      }
    }
  }

  credential_provider_configuration {
    oauth {
      provider_arn = aws_bedrockagentcore_oauth2_credential_provider.gateway_m2m.credential_provider_arn
      scopes       = aws_cognito_resource_server.mcp.scope_identifiers
    }
  }
}
