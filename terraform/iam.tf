# ---------------------------------------------------------------------------
# IAM execution role for the AgentCore runtime
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
# AWS managed ReadOnlyAccess -- covers all Describe/List/Get across services
# Used by describe_account, get_spending, and search_logs tools
# ---------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "readonly" {
  role       = aws_iam_role.runtime.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# ---------------------------------------------------------------------------
# Additional write permissions (not covered by ReadOnlyAccess)
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

  # CloudFormation -- stack management
  statement {
    sid    = "CloudFormationManagement"
    effect = "Allow"
    actions = [
      "cloudformation:CreateStack",
      "cloudformation:UpdateStack",
      "cloudformation:DeleteStack",
      "cloudformation:CreateChangeSet",
      "cloudformation:ExecuteChangeSet",
      "cloudformation:DeleteChangeSet",
      "cloudformation:DescribeChangeSet",
      "cloudformation:DescribeStacks",
      "cloudformation:DescribeStackEvents",
      "cloudformation:ListStacks",
      "cloudformation:ListStackResources",
      "cloudformation:GetTemplate",
      "cloudformation:GetTemplateSummary",
      "cloudformation:ValidateTemplate",
      "cloudformation:TagResource",
    ]
    resources = ["*"]
  }

  # IAM for CloudFormation-created roles (scoped to agentcore-cf-* prefix)
  statement {
    sid    = "IAMForCloudFormation"
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

  # Resource creation permissions for CloudFormation-managed services
  statement {
    sid    = "ResourceCreation"
    effect = "Allow"
    actions = [
      # DynamoDB
      "dynamodb:CreateTable",
      "dynamodb:DeleteTable",
      "dynamodb:UpdateTable",
      "dynamodb:DescribeTable",
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
      "sqs:TagQueue",
      # SNS
      "sns:CreateTopic",
      "sns:DeleteTopic",
      "sns:Subscribe",
      "sns:Unsubscribe",
      "sns:SetTopicAttributes",
      "sns:TagResource",
      # CloudWatch
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:PutDashboard",
      "cloudwatch:DeleteDashboards",
      # CloudWatch Logs (for Lambda log groups)
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:TagResource",
      # EC2 (security groups)
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:CreateTags",
      # Step Functions
      "states:CreateStateMachine",
      "states:DeleteStateMachine",
      "states:UpdateStateMachine",
      "states:TagResource",
      # EventBridge
      "events:PutRule",
      "events:DeleteRule",
      "events:PutTargets",
      "events:RemoveTargets",
      "events:TagResource",
    ]
    resources = ["*"]
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
      aws_bedrockagentcore_memory.demo.arn,
      "${aws_bedrockagentcore_memory.demo.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "runtime" {
  name   = "${local.name}-runtime-policy"
  role   = aws_iam_role.runtime.id
  policy = data.aws_iam_policy_document.runtime_write_permissions.json
}
