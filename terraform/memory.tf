# ---------------------------------------------------------------------------
# AgentCore Memory -- session persistence across invocations
# ---------------------------------------------------------------------------

resource "aws_bedrockagentcore_memory" "demo" {
  name                  = replace("${local.name}-memory", "-", "_")
  description           = "Session memory for the Infrastructure Bootstrapper agent"
  event_expiry_duration = var.memory_event_expiry_days

  tags = { Project = var.project_name }
}

resource "aws_bedrockagentcore_memory_strategy" "summarization" {
  name      = replace("${local.name}-summarization", "-", "_")
  memory_id = aws_bedrockagentcore_memory.demo.id
  type      = "SUMMARIZATION"

  description = "Summarize infrastructure sessions into long-term memory"
  namespaces  = ["strategies/{memoryStrategyId}/actors/{actorId}/sessions/{sessionId}"]
}
