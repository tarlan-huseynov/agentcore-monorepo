output "runtime_id" {
  description = "Agent Runtime ID"
  value       = aws_bedrockagentcore_agent_runtime.demo.agent_runtime_id
}

output "runtime_arn" {
  description = "Agent Runtime ARN"
  value       = aws_bedrockagentcore_agent_runtime.demo.agent_runtime_arn
}

output "gateway_id" {
  description = "AgentCore Gateway ID"
  value       = aws_bedrockagentcore_gateway.main.gateway_id
}

output "gateway_url" {
  description = "AgentCore Gateway MCP endpoint URL"
  value       = aws_bedrockagentcore_gateway.main.gateway_url
}

output "ccapi_runtime_id" {
  description = "CCAPI MCP Server Runtime ID"
  value       = aws_bedrockagentcore_agent_runtime.ccapi.agent_runtime_id
}

output "cost_runtime_id" {
  description = "Cost Explorer MCP Server Runtime ID"
  value       = aws_bedrockagentcore_agent_runtime.cost_explorer.agent_runtime_id
}

output "s3_bucket" {
  description = "S3 bucket for deployment code"
  value       = aws_s3_bucket.code.id
}

output "memory_id" {
  description = "AgentCore Memory resource ID"
  value       = aws_bedrockagentcore_memory.demo.id
}

output "summarization_strategy_id" {
  description = "Memory summarization strategy ID"
  value       = aws_bedrockagentcore_memory_strategy.summarization.memory_strategy_id
}

output "iam_role_arn" {
  description = "Agent IAM execution role ARN"
  value       = aws_iam_role.runtime.arn
}

output "invoke_command" {
  description = "AWS CLI command to invoke the deployed agent (requires AWS CLI >= 2.31.13)"
  value       = <<-EOT
    aws bedrock-agentcore invoke-agent-runtime \
      --agent-runtime-arn "${aws_bedrockagentcore_agent_runtime.demo.agent_runtime_arn}" \
      --content-type "application/json" \
      --accept "application/json" \
      --payload '{"prompt": "List my S3 buckets"}' \
      response.json && cat response.json
  EOT
}
