# ---------------------------------------------------------------------------
# MCP Server Runtimes — CCAPI and Cost Explorer
#
# Each runs as an AgentCore Runtime with MCP protocol, serving as a target
# for the AgentCore Gateway.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Runtime: Cloud Control API MCP Server
# ---------------------------------------------------------------------------

resource "aws_bedrockagentcore_agent_runtime" "ccapi" {
  agent_runtime_name = replace("${local.name}-ccapi-mcp", "-", "_")
  description        = "Cloud Control API MCP Server"
  role_arn           = aws_iam_role.mcp_ccapi.arn

  agent_runtime_artifact {
    code_configuration {
      entry_point = ["ccapi_entrypoint.py"]
      runtime     = var.python_runtime

      code {
        s3 {
          bucket = aws_s3_bucket.code.id
          prefix = aws_s3_object.ccapi_package.key
        }
      }
    }
  }

  protocol_configuration {
    server_protocol = "MCP"
  }

  network_configuration {
    network_mode = "PUBLIC"
  }

  environment_variables = {
    AWS_REGION        = local.region
    SECURITY_SCANNING = "enabled"
    DEFAULT_TAGS      = "enabled"
    FASTMCP_LOG_LEVEL = var.log_level
    _CODE_VERSION     = null_resource.build_ccapi.triggers.source_hash
  }

  depends_on = [
    aws_iam_role_policy.mcp_ccapi,
    aws_s3_object.ccapi_package,
  ]
}

# ---------------------------------------------------------------------------
# Runtime: Cost Explorer MCP Server
# ---------------------------------------------------------------------------

resource "aws_bedrockagentcore_agent_runtime" "cost_explorer" {
  agent_runtime_name = replace("${local.name}-cost-mcp", "-", "_")
  description        = "Cost Explorer MCP Server"
  role_arn           = aws_iam_role.mcp_cost.arn

  agent_runtime_artifact {
    code_configuration {
      entry_point = ["cost_entrypoint.py"]
      runtime     = var.python_runtime

      code {
        s3 {
          bucket = aws_s3_bucket.code.id
          prefix = aws_s3_object.cost_package.key
        }
      }
    }
  }

  protocol_configuration {
    server_protocol = "MCP"
  }

  network_configuration {
    network_mode = "PUBLIC"
  }

  environment_variables = {
    AWS_REGION        = local.region
    FASTMCP_LOG_LEVEL = var.log_level
    _CODE_VERSION     = null_resource.build_cost.triggers.source_hash
  }

  depends_on = [
    aws_iam_role_policy.mcp_cost,
    aws_s3_object.cost_package,
  ]
}
