# ---------------------------------------------------------------------------
# IAM execution role for the Agent Runtime (orchestrator)
#
# Simplified: infrastructure management permissions moved to CCAPI MCP Server
# role (gateway_iam.tf). This role only needs Bedrock invoke, S3 code access,
# Memory, logging, and ReadOnlyAccess for search_logs.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["bedrock-agentcore.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:bedrock-agentcore:${local.region}:${local.account_id}:*"]
    }
  }
}

resource "aws_iam_role" "runtime" {
  name               = "${local.name}-runtime-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# ---------------------------------------------------------------------------
# AWS managed ReadOnlyAccess -- covers Describe/List/Get for search_logs
# ---------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "readonly" {
  role       = aws_iam_role.runtime.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# ---------------------------------------------------------------------------
# Additional permissions (Bedrock invoke, S3, Memory, logging)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "runtime_write_permissions" {

  # CloudWatch Logs -- AgentCore runtime logging (write)
  statement {
    sid    = "CloudWatchLogsWrite"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:PutRetentionPolicy",
    ]
    resources = [
      "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/bedrock-agentcore/runtimes/*",
      "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/bedrock-agentcore/runtimes/*:log-stream:*",
    ]
  }

  # X-Ray tracing
  statement {
    sid    = "XRayTracing"
    effect = "Allow"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
    ]
    resources = ["*"]
  }

  # CloudWatch Metrics
  statement {
    sid       = "CloudWatchMetrics"
    effect    = "Allow"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["bedrock-agentcore"]
    }
  }

  # Bedrock model invocation (Claude models)
  statement {
    sid    = "BedrockInvoke"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
    ]
    resources = [
      "arn:aws:bedrock:*::foundation-model/anthropic.claude-*",
      "arn:aws:bedrock:*:${local.account_id}:inference-profile/${local.bedrock_region_prefix}.anthropic.claude-*",
    ]
  }

  # S3 -- read deployment artifact
  statement {
    sid       = "S3CodeAccess"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.code.arn}/*"]
  }

  # AgentCore Memory -- session event read/write
  statement {
    sid    = "AgentCoreMemory"
    effect = "Allow"
    actions = [
      "bedrock-agentcore:CreateEvent",
      "bedrock-agentcore:GetEvent",
      "bedrock-agentcore:ListEvents",
      "bedrock-agentcore:DeleteEvent",
      "bedrock-agentcore:RetrieveMemoryRecords",
    ]
    resources = [
      aws_bedrockagentcore_memory.main.arn,
      "${aws_bedrockagentcore_memory.main.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "runtime" {
  name   = "${local.name}-runtime-policy"
  role   = aws_iam_role.runtime.id
  policy = data.aws_iam_policy_document.runtime_write_permissions.json
}
