// ---------------------------------------------------------------------------
// AgentCore Policy: Safety guardrails for the Infrastructure Bootstrapper
//
// Enforced at the Gateway level — every MCP tool call is checked before
// reaching the MCP server. Default deny: only explicitly permitted actions
// are allowed.
//
// Action format: TargetName___tool_name (three underscores)
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// 1. CCAPI MCP Server — read-only tools (always allowed)
// ---------------------------------------------------------------------------

permit(
    principal,
    action in [
        AgentCore::Action::"ccapi-mcp-server___check_environment_variables",
        AgentCore::Action::"ccapi-mcp-server___get_aws_session_info",
        AgentCore::Action::"ccapi-mcp-server___get_aws_account_info",
        AgentCore::Action::"ccapi-mcp-server___get_resource_schema_information",
        AgentCore::Action::"ccapi-mcp-server___list_resources",
        AgentCore::Action::"ccapi-mcp-server___get_resource",
        AgentCore::Action::"ccapi-mcp-server___get_resource_request_status",
        AgentCore::Action::"ccapi-mcp-server___explain",
        AgentCore::Action::"ccapi-mcp-server___run_checkov",
        AgentCore::Action::"ccapi-mcp-server___generate_infrastructure_code",
        AgentCore::Action::"ccapi-mcp-server___create_template"
    ],
    resource
);

// ---------------------------------------------------------------------------
// 2. CCAPI MCP Server — create/update restricted to safe resource types
//
// Covers BOTH the raw tools (use `resourceType`) and the bundled workflow
// tools prepare_/confirm_resource_creation (use `resource_type`). Bundled
// tools exist because stateless_http=True isolates each MCP call; they run
// the full token chain in one request. Cedar must permit the entry point.
// ---------------------------------------------------------------------------

permit(
    principal,
    action in [
        AgentCore::Action::"ccapi-mcp-server___create_resource",
        AgentCore::Action::"ccapi-mcp-server___update_resource"
    ],
    resource
)
when {
    context.input has resourceType &&
    (context.input.resourceType == "AWS::DynamoDB::Table" ||
     context.input.resourceType == "AWS::S3::Bucket" ||
     context.input.resourceType == "AWS::SQS::Queue" ||
     context.input.resourceType == "AWS::SNS::Topic" ||
     context.input.resourceType == "AWS::Lambda::Function" ||
     context.input.resourceType == "AWS::Events::Rule" ||
     context.input.resourceType == "AWS::CloudWatch::Alarm" ||
     context.input.resourceType == "AWS::ApiGateway::RestApi" ||
     context.input.resourceType == "AWS::StepFunctions::StateMachine" ||
     context.input.resourceType == "AWS::Logs::LogGroup" ||
     context.input.resourceType == "AWS::EC2::Instance")
};

permit(
    principal,
    action in [
        AgentCore::Action::"ccapi-mcp-server___prepare_resource_creation",
        AgentCore::Action::"ccapi-mcp-server___confirm_resource_creation"
    ],
    resource
)
when {
    context.input has resource_type &&
    (context.input.resource_type == "AWS::DynamoDB::Table" ||
     context.input.resource_type == "AWS::S3::Bucket" ||
     context.input.resource_type == "AWS::SQS::Queue" ||
     context.input.resource_type == "AWS::SNS::Topic" ||
     context.input.resource_type == "AWS::Lambda::Function" ||
     context.input.resource_type == "AWS::Events::Rule" ||
     context.input.resource_type == "AWS::CloudWatch::Alarm" ||
     context.input.resource_type == "AWS::ApiGateway::RestApi" ||
     context.input.resource_type == "AWS::StepFunctions::StateMachine" ||
     context.input.resource_type == "AWS::Logs::LogGroup" ||
     context.input.resource_type == "AWS::EC2::Instance")
};

// ---------------------------------------------------------------------------
// 3. CCAPI MCP Server — delete restricted to non-critical resource types
// ---------------------------------------------------------------------------

permit(
    principal,
    action == AgentCore::Action::"ccapi-mcp-server___delete_resource",
    resource
)
when {
    context.input has resourceType &&
    (context.input.resourceType == "AWS::DynamoDB::Table" ||
     context.input.resourceType == "AWS::SQS::Queue" ||
     context.input.resourceType == "AWS::SNS::Topic" ||
     context.input.resourceType == "AWS::CloudWatch::Alarm" ||
     context.input.resourceType == "AWS::Logs::LogGroup" ||
     context.input.resourceType == "AWS::EC2::Instance")
};

permit(
    principal,
    action in [
        AgentCore::Action::"ccapi-mcp-server___prepare_resource_deletion",
        AgentCore::Action::"ccapi-mcp-server___confirm_resource_deletion"
    ],
    resource
)
when {
    context.input has resource_type &&
    (context.input.resource_type == "AWS::DynamoDB::Table" ||
     context.input.resource_type == "AWS::SQS::Queue" ||
     context.input.resource_type == "AWS::SNS::Topic" ||
     context.input.resource_type == "AWS::CloudWatch::Alarm" ||
     context.input.resource_type == "AWS::Logs::LogGroup" ||
     context.input.resource_type == "AWS::EC2::Instance")
};

// ---------------------------------------------------------------------------
// 4. Cost Explorer MCP Server — all tools allowed (read-only by nature)
// ---------------------------------------------------------------------------

permit(
    principal,
    action in [
        AgentCore::Action::"cost-explorer-mcp-server___get_today_date",
        AgentCore::Action::"cost-explorer-mcp-server___get_cost_and_usage",
        AgentCore::Action::"cost-explorer-mcp-server___get_cost_forecast",
        AgentCore::Action::"cost-explorer-mcp-server___get_dimension_values",
        AgentCore::Action::"cost-explorer-mcp-server___get_tag_values",
        AgentCore::Action::"cost-explorer-mcp-server___get_cost_and_usage_comparisons",
        AgentCore::Action::"cost-explorer-mcp-server___get_cost_comparison_drivers"
    ],
    resource
);
