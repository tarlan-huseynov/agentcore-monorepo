# ---------------------------------------------------------------------------
# CloudWatch log group for application logs
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/aws/bedrock-agentcore/runtimes/${local.name}-app-logs"
  retention_in_days = 7

  tags = { Project = var.project_name }
}
