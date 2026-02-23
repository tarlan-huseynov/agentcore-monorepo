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

data "aws_iam_policy_document" "mcp_ccapi_permissions" {
  # Cloud Control API — full CRUDL
  statement {
    sid    = "CloudControlAPI"
    effect = "Allow"
    actions = [
      "cloudcontrol:CreateResource",
      "cloudcontrol:GetResource",
      "cloudcontrol:UpdateResource",
      "cloudcontrol:DeleteResource",
      "cloudcontrol:ListResources",
      "cloudcontrol:GetResourceRequestStatus",
      "cloudcontrol:ListResourceRequests",
    ]
    resources = ["*"]
  }

  # CloudFormation — IaC generator + schema
  statement {
    sid    = "CloudFormationIaC"
    effect = "Allow"
    actions = [
      "cloudformation:CreateGeneratedTemplate",
      "cloudformation:DescribeGeneratedTemplate",
      "cloudformation:GetGeneratedTemplate",
      "cloudformation:ListGeneratedTemplates",
      "cloudformation:DeleteGeneratedTemplate",
      "cloudformation:DescribeType",
      "cloudformation:ListTypes",
    ]
    resources = ["*"]
  }

  # Service permissions for Cloud Control managed resources
  statement {
    sid    = "ServicePermissions"
    effect = "Allow"
    actions = [
      # DynamoDB
      "dynamodb:CreateTable",
      "dynamodb:DeleteTable",
      "dynamodb:UpdateTable",
      "dynamodb:DescribeTable",
      "dynamodb:ListTables",
      "dynamodb:TagResource",
      "dynamodb:UntagResource",
      "dynamodb:UpdateTimeToLive",
      "dynamodb:DescribeTimeToLive",
      # Lambda
      "lambda:CreateFunction",
      "lambda:DeleteFunction",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:AddPermission",
      "lambda:RemovePermission",
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
      "lambda:ListFunctions",
      "lambda:TagResource",
      "lambda:PutFunctionEventInvokeConfig",
      "lambda:CreateEventSourceMapping",
      "lambda:DeleteEventSourceMapping",
      # API Gateway
      "apigateway:POST",
      "apigateway:GET",
      "apigateway:PUT",
      "apigateway:DELETE",
      "apigateway:PATCH",
      # S3
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:ListAllMyBuckets",
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:PutBucketTagging",
      "s3:PutEncryptionConfiguration",
      "s3:PutBucketVersioning",
      "s3:PutBucketPublicAccessBlock",
      # SQS
      "sqs:CreateQueue",
      "sqs:DeleteQueue",
      "sqs:SetQueueAttributes",
      "sqs:GetQueueAttributes",
      "sqs:ListQueues",
      "sqs:TagQueue",
      # SNS
      "sns:CreateTopic",
      "sns:DeleteTopic",
      "sns:Subscribe",
      "sns:Unsubscribe",
      "sns:SetTopicAttributes",
      "sns:ListTopics",
      "sns:TagResource",
      # CloudWatch
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:PutDashboard",
      "cloudwatch:DeleteDashboards",
      "cloudwatch:DescribeAlarms",
      # CloudWatch Logs (for Lambda log groups)
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:DescribeLogGroups",
      "logs:TagResource",
      # EC2 (security groups, VPC basics)
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeInstances",
      "ec2:DescribeVpcs",
      "ec2:DescribeSubnets",
      "ec2:CreateTags",
      # Step Functions
      "states:CreateStateMachine",
      "states:DeleteStateMachine",
      "states:UpdateStateMachine",
      "states:DescribeStateMachine",
      "states:ListStateMachines",
      "states:TagResource",
      # EventBridge
      "events:PutRule",
      "events:DeleteRule",
      "events:PutTargets",
      "events:RemoveTargets",
      "events:ListRules",
      "events:TagResource",
    ]
    resources = ["*"]
  }

  # IAM for created roles (scoped to agentcore-cf-* prefix)
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

resource "aws_iam_role_policy" "mcp_ccapi" {
  name   = "${local.name}-mcp-ccapi-policy"
  role   = aws_iam_role.mcp_ccapi.id
  policy = data.aws_iam_policy_document.mcp_ccapi_permissions.json
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
