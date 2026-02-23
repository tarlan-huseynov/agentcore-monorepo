# ---------------------------------------------------------------------------
# AgentCore Agent Runtime
#
# This is the core resource.  Declare the desired state once, change one
# field, run `terraform apply`, and only that field changes.
# ---------------------------------------------------------------------------

resource "aws_bedrockagentcore_agent_runtime" "main" {
  agent_runtime_name = replace(var.project_name, "-", "_")
  description        = "Infrastructure Bootstrapper: Strands Agent + Gateway MCP + Bedrock + Memory"
  role_arn           = aws_iam_role.runtime.arn

  agent_runtime_artifact {
    code_configuration {
      entry_point = ["app/entrypoint.py"]
      runtime     = var.python_runtime

      code {
        s3 {
          bucket = aws_s3_bucket.code.id
          prefix = aws_s3_object.deployment_package.key
        }
      }
    }
  }

  protocol_configuration {
    server_protocol = "HTTP"
  }

  network_configuration {
    network_mode = "PUBLIC"
  }

  environment_variables = {
    LOG_LEVEL                        = var.log_level
    BEDROCK_MODEL_ID                 = local.bedrock_model_id
    MEMORY_ENABLED                   = "true"
    MEMORY_ID                        = aws_bedrockagentcore_memory.main.id
    MEMORY_SUMMARIZATION_STRATEGY_ID = aws_bedrockagentcore_memory_strategy.summarization.memory_strategy_id
    GATEWAY_URL                      = aws_bedrockagentcore_gateway.main.gateway_url

    # Force runtime update when code changes.  AgentCore caches S3 code at
    # deploy time -- simply updating the S3 object won't trigger a redeploy.
    # Changing an env var forces the runtime to re-fetch code from S3.
    _CODE_VERSION = null_resource.build.triggers.source_hash
  }

  depends_on = [
    aws_iam_role_policy.runtime,
    aws_s3_object.deployment_package,
  ]
}
