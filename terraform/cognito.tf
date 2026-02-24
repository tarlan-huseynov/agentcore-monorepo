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
# ---------------------------------------------------------------------------

resource "aws_bedrockagentcore_oauth2_credential_provider" "gateway_m2m" {
  name                       = "${local.name}-m2m-oauth2"
  credential_provider_vendor = "CustomOauth2"

  oauth2_provider_config {
    custom_oauth2_provider_config {
      client_id     = aws_cognito_user_pool_client.m2m.id
      client_secret = aws_cognito_user_pool_client.m2m.client_secret

      oauth_discovery {
        discovery_url = "https://cognito-idp.${local.region}.amazonaws.com/${aws_cognito_user_pool.gateway_outbound.id}/.well-known/openid-configuration"
      }
    }
  }
}
