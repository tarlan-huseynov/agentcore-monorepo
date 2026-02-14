# ---------------------------------------------------------------------------
# AgentCore Agent Runtime
#
# This is the core resource.  Compare this declarative block to the 130-line
# deploy.sh in the ATHENA project that must read-modify-write every field.
# With Terraform, you declare the desired state once.  Change one field,
# run `terraform apply`, and only that field changes.
# ---------------------------------------------------------------------------

resource "aws_bedrockagentcore_agent_runtime" "demo" {
  agent_runtime_name = replace(var.project_name, "-", "_")
  description        = "Demo: Strands Agents + Bedrock + AgentCore Memory (Terraform-deployed)"
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
    ENVIRONMENT                      = "agentcore"
    LOG_LEVEL                        = var.log_level
    AWS_REGION                       = local.region
    BEDROCK_MODEL_ID                 = var.bedrock_model_id
    MEMORY_ENABLED                   = "true"
    MEMORY_ID                        = aws_bedrockagentcore_memory.demo.id
    MEMORY_SUMMARIZATION_STRATEGY_ID = aws_bedrockagentcore_memory_strategy.summarization.memory_strategy_id

    # Force runtime update when code changes.  AgentCore caches S3 code at
    # deploy time -- simply updating the S3 object won't trigger a redeploy.
    # Changing an env var forces the runtime to re-fetch code from S3.
    _CODE_VERSION = aws_s3_object.deployment_package.etag
  }

  depends_on = [
    aws_iam_role_policy.runtime,
    aws_s3_object.deployment_package,
  ]
}
