output "runtime_id" {
  description = "AgentCore Runtime ID"
  value       = aws_bedrockagentcore_agent_runtime.demo.agent_runtime_id
}

output "runtime_arn" {
  description = "AgentCore Runtime ARN"
  value       = aws_bedrockagentcore_agent_runtime.demo.agent_runtime_arn
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
  description = "IAM execution role ARN"
  value       = aws_iam_role.runtime.arn
}

output "invoke_command" {
  description = "AWS CLI command to invoke the deployed agent"
  value       = <<-EOT
    aws bedrock-agentcore-runtime invoke-agent-runtime \
      --agent-runtime-id ${aws_bedrockagentcore_agent_runtime.demo.agent_runtime_id} \
      --runtime-endpoint-id DEFAULT \
      --payload '{"prompt": "What is the weather in Tokyo?"}' \
      --output text
  EOT
}
