# ---------------------------------------------------------------------------
# AgentCore Policy — Cedar-based safety guardrails
#
# No native Terraform resource exists for Policy Engine/Policy as of
# provider ~> 6.32. We use a null_resource with a shell script that calls
# the AWS CLI (bedrock-agentcore-control) to:
#   1. Create a policy engine
#   2. Create the Cedar safety policy
#   3. Attach the engine to the Gateway in ENFORCE mode
#
# The Cedar policy (policies/safety.cedar) restricts:
#   - create/update to safe resource types (DynamoDB, S3, SQS, SNS, Lambda, etc.)
#   - delete to non-critical resource types only
#   - all read-only and cost tools are always permitted
# ---------------------------------------------------------------------------

resource "null_resource" "policy_setup" {
  triggers = {
    # Re-run when the Cedar policy file changes
    policy_hash = filesha256("${path.module}/policies/safety.cedar")
    gateway_id  = aws_bedrockagentcore_gateway.main.gateway_id
  }

  provisioner "local-exec" {
    command     = "bash scripts/setup_policy.sh"
    working_dir = "${path.module}/.."

    environment = {
      GATEWAY_ID  = aws_bedrockagentcore_gateway.main.gateway_id
      GATEWAY_ARN = aws_bedrockagentcore_gateway.main.gateway_arn
      ENGINE_NAME = replace("${local.name}-policy-engine", "-", "_")
      POLICY_NAME = replace("${local.name}-safety-policy", "-", "_")
    }
  }

  # Re-run when the gateway or targets are recreated/replaced, since
  # gateway updates strip the policy engine (not in TF schema).
  lifecycle {
    replace_triggered_by = [
      aws_bedrockagentcore_gateway.main,
      null_resource.gateway_targets,
    ]
  }

  depends_on = [
    aws_bedrockagentcore_gateway.main,
    null_resource.gateway_targets,
  ]
}
