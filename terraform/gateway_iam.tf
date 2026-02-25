# ---------------------------------------------------------------------------
# IAM roles for Gateway + MCP server Runtimes
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 1. Gateway role — allows Gateway to operate
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "gateway_assume_role" {
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
      values   = ["arn:aws:bedrock-agentcore:${local.region}:${local.account_id}:gateway/*"]
    }
  }
}

resource "aws_iam_role" "gateway" {
  name               = "${local.name}-gateway-role"
  assume_role_policy = data.aws_iam_policy_document.gateway_assume_role.json
}

data "aws_iam_policy_document" "gateway_permissions" {
  # Invoke MCP server Runtimes
  statement {
    sid    = "InvokeMCPRuntimes"
    effect = "Allow"
    actions = [
      "bedrock-agentcore:InvokeAgentRuntime",
    ]
    resources = [
      aws_bedrockagentcore_agent_runtime.ccapi.agent_runtime_arn,
      aws_bedrockagentcore_agent_runtime.cost_explorer.agent_runtime_arn,
    ]
  }

  # Policy Engine — evaluate Cedar policies at the Gateway.
  # AuthorizeAction: evaluates a single tool call against Cedar policies.
  # PartiallyAuthorizeActions: filters tools/list to only permitted tools.
  statement {
    sid    = "PolicyEngine"
    effect = "Allow"
    actions = [
      "bedrock-agentcore:GetPolicyEngine",
      "bedrock-agentcore:GetPolicy",
      "bedrock-agentcore:IsAuthorized",
      "bedrock-agentcore:AuthorizeAction",
      "bedrock-agentcore:PartiallyAuthorizeActions",
    ]
    resources = ["*"]
  }

  # Outbound OAuth — required for Gateway to fetch Bearer tokens for target runtimes.
  # The Gateway needs: workload identity access, OAuth2 token retrieval, and
  # Secrets Manager access (credential provider stores client_secret there).
  statement {
    sid    = "OutboundOAuth"
    effect = "Allow"
    actions = [
      "bedrock-agentcore:GetWorkloadAccessToken",
      "bedrock-agentcore:GetResourceOauth2Token",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "SecretsManagerOAuth"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = [
      "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:bedrock-agentcore*",
    ]
  }

  # CloudWatch Logs for Gateway
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/bedrock-agentcore/gateways/*",
      "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/bedrock-agentcore/gateways/*:log-stream:*",
    ]
  }
}

resource "aws_iam_role_policy" "gateway" {
  name   = "${local.name}-gateway-policy"
  role   = aws_iam_role.gateway.id
  policy = data.aws_iam_policy_document.gateway_permissions.json
}

# ---------------------------------------------------------------------------
# 2. CCAPI MCP Server role — Cloud Control API + service permissions
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "mcp_ccapi_assume_role" {
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

resource "aws_iam_role" "mcp_ccapi" {
  name               = "${local.name}-mcp-ccapi-role"
  assume_role_policy = data.aws_iam_policy_document.mcp_ccapi_assume_role.json
}

# PowerUserAccess covers all services except IAM/Organizations.
# Replaces per-service action lists with a single managed policy.
# Safety guardrails come from Cedar policy at the Gateway level.
resource "aws_iam_role_policy_attachment" "mcp_ccapi_power_user" {
  role       = aws_iam_role.mcp_ccapi.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# Scoped IAM — only for roles the agent creates (agentcore-cf-* prefix).
# PowerUserAccess excludes most IAM actions.
data "aws_iam_policy_document" "mcp_ccapi_iam" {
  statement {
    sid    = "IAMForCreatedRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PassRole",
      "iam:TagRole",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:GetRolePolicy",
    ]
    resources = [
      "arn:aws:iam::${local.account_id}:role/agentcore-cf-*",
    ]
  }
}

resource "aws_iam_role_policy" "mcp_ccapi_iam" {
  name   = "${local.name}-mcp-ccapi-iam"
  role   = aws_iam_role.mcp_ccapi.id
  policy = data.aws_iam_policy_document.mcp_ccapi_iam.json
}

# ---------------------------------------------------------------------------
# 3. Cost Explorer MCP Server role — read-only cost data
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "mcp_cost_assume_role" {
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

resource "aws_iam_role" "mcp_cost" {
  name               = "${local.name}-mcp-cost-role"
  assume_role_policy = data.aws_iam_policy_document.mcp_cost_assume_role.json
}

data "aws_iam_policy_document" "mcp_cost_permissions" {
  # Cost Explorer — read-only spending data
  statement {
    sid    = "CostExplorer"
    effect = "Allow"
    actions = [
      "ce:GetCostAndUsage",
      "ce:GetCostForecast",
      "ce:GetDimensionValues",
      "ce:GetTags",
      "ce:GetCostAndUsageComparisons",
      "ce:GetCostComparisonDrivers",
    ]
    resources = ["*"]
  }

  # CloudWatch Logs — runtime logging
  statement {
    sid    = "RuntimeLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/bedrock-agentcore/runtimes/*",
      "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/bedrock-agentcore/runtimes/*:log-stream:*",
    ]
  }
}

resource "aws_iam_role_policy" "mcp_cost" {
  name   = "${local.name}-mcp-cost-policy"
  role   = aws_iam_role.mcp_cost.id
  policy = data.aws_iam_policy_document.mcp_cost_permissions.json
}
