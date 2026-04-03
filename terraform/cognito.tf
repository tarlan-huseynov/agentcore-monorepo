# ---------------------------------------------------------------------------
# Cognito User Pool for Gateway → MCP Server outbound M2M authentication
#
# MCP server gateway targets require OAuth credential providers.
# We use a Cognito User Pool with client_credentials grant for M2M auth.
# ---------------------------------------------------------------------------

resource "aws_cognito_user_pool" "gateway_outbound" {
  name                = "${local.name}-gateway-outbound"
  deletion_protection = "INACTIVE"

  tags = { Project = var.project_name }
}

# Resource server defines the scopes the Gateway can request
resource "aws_cognito_resource_server" "mcp" {
  identifier   = "mcp"
  name         = "MCP Server Access"
  user_pool_id = aws_cognito_user_pool.gateway_outbound.id

  scope {
    scope_name        = "invoke"
    scope_description = "Invoke MCP server tools"
  }
}

# Domain required for token endpoint
resource "aws_cognito_user_pool_domain" "gateway_outbound" {
  domain       = "${local.name}-gw-${local.account_id}"
  user_pool_id = aws_cognito_user_pool.gateway_outbound.id
}

# M2M client — client_credentials grant only
resource "aws_cognito_user_pool_client" "m2m" {
  name         = "${local.name}-gateway-m2m"
  user_pool_id = aws_cognito_user_pool.gateway_outbound.id

  generate_secret              = true
  allowed_oauth_flows          = ["client_credentials"]
  allowed_oauth_scopes         = aws_cognito_resource_server.mcp.scope_identifiers
  allowed_oauth_flows_user_pool_client = true

  explicit_auth_flows = []

  depends_on = [aws_cognito_resource_server.mcp]
}

# ---------------------------------------------------------------------------
# AgentCore OAuth2 Credential Provider — used by Gateway targets
#
# Managed via AWS CLI because the Terraform provider (~> 6.39) has a bug:
# the Read function calls ListTagsForResource with the credential provider
# ARN, but the AgentCore API returns "Invalid input resource arn" for this
# resource type, making terraform plan fail on every refresh.
# ---------------------------------------------------------------------------

locals {
  oauth2_provider_name = "${local.name}-m2m-oauth2"
}

resource "null_resource" "oauth2_credential_provider" {
  triggers = {
    name           = local.oauth2_provider_name
    client_id      = aws_cognito_user_pool_client.m2m.id
    client_secret  = aws_cognito_user_pool_client.m2m.client_secret
    discovery_url  = "https://cognito-idp.${local.region}.amazonaws.com/${aws_cognito_user_pool.gateway_outbound.id}/.well-known/openid-configuration"
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command = <<-EOT
      set -euo pipefail

      # Check if provider already exists
      EXISTING_ARN=$(aws bedrock-agentcore-control list-oauth2-credential-providers \
        --query "credentialProviders[?name=='${local.oauth2_provider_name}'].credentialProviderArn | [0]" \
        --output text 2>/dev/null || echo "None")

      if [ "$EXISTING_ARN" != "None" ] && [ -n "$EXISTING_ARN" ]; then
        echo "OAuth2 credential provider already exists: $EXISTING_ARN"
        exit 0
      fi

      # Create the credential provider
      RESULT=$(aws bedrock-agentcore-control create-oauth2-credential-provider \
        --name "${local.oauth2_provider_name}" \
        --credential-provider-vendor "CustomOauth2" \
        --oauth2-provider-config "{
          \"customOauth2ProviderConfig\": {
            \"clientId\": \"${aws_cognito_user_pool_client.m2m.id}\",
            \"clientSecret\": \"${aws_cognito_user_pool_client.m2m.client_secret}\",
            \"oauthDiscovery\": {
              \"discoveryUrl\": \"https://cognito-idp.${local.region}.amazonaws.com/${aws_cognito_user_pool.gateway_outbound.id}/.well-known/openid-configuration\"
            }
          }
        }" --output json 2>&1)

      ARN=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['credentialProviderArn'])")
      echo "Created: $ARN"
    EOT
  }

  depends_on = [
    aws_cognito_user_pool_client.m2m,
    aws_cognito_user_pool.gateway_outbound,
  ]
}

data "external" "oauth2_provider_arn" {
  program = [
    "bash", "-c",
    <<-EOT
      ARN=$(aws bedrock-agentcore-control list-oauth2-credential-providers \
        --query "credentialProviders[?name=='${local.oauth2_provider_name}'].credentialProviderArn | [0]" \
        --output text 2>/dev/null)
      echo "{\"arn\": \"$ARN\"}"
    EOT
  ]

  depends_on = [null_resource.oauth2_credential_provider]
}
