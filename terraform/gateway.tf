# ---------------------------------------------------------------------------
# AgentCore Gateway — single MCP endpoint aggregating CCAPI + Cost Explorer
# ---------------------------------------------------------------------------

resource "aws_bedrockagentcore_gateway" "main" {
  name            = replace("${local.name}-gateway", "-", "_")
  description     = "MCP Gateway: CCAPI + Cost Explorer tools"
  role_arn        = aws_iam_role.gateway.arn
  protocol_type   = "MCP"
  authorizer_type = "NONE" # Demo simplicity; production would use AWS_IAM

  protocol_configuration {
    mcp {
      instructions       = "Gateway for infrastructure management and cost analysis"
      search_type        = "HYBRID"
      supported_versions = ["2025-03-26", "2025-06-18"]
    }
  }

  tags = { Project = var.project_name }
}

# ---------------------------------------------------------------------------
# Gateway Targets — each points to an MCP server Runtime
# ---------------------------------------------------------------------------

resource "aws_bedrockagentcore_gateway_target" "ccapi" {
  name               = "ccapi_mcp_server"
  description        = "Cloud Control API — infrastructure CRUDL for 1100+ resource types"
  gateway_identifier = aws_bedrockagentcore_gateway.main.gateway_id

  target_configuration {
    mcp {
      mcp_server {
        endpoint = "https://${aws_bedrockagentcore_agent_runtime.ccapi.agent_runtime_endpoint}/mcp"
      }
    }
  }

  credential_provider_configuration {
    gateway_iam_role {}
  }
}

resource "aws_bedrockagentcore_gateway_target" "cost_explorer" {
  name               = "cost_explorer_mcp_server"
  description        = "AWS Cost Explorer — spending analysis and forecasts"
  gateway_identifier = aws_bedrockagentcore_gateway.main.gateway_id

  target_configuration {
    mcp {
      mcp_server {
        endpoint = "https://${aws_bedrockagentcore_agent_runtime.cost_explorer.agent_runtime_endpoint}/mcp"
      }
    }
  }

  credential_provider_configuration {
    gateway_iam_role {}
  }
}
