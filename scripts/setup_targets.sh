#!/usr/bin/env bash
# Create or update Gateway targets via AWS CLI.
#
# Called by Terraform null_resource provisioner.
# The Terraform provider (~> 6.32) does not support grantType on the OAuth
# credential provider, which is required for the Gateway to fetch Bearer tokens.
# We manage targets via CLI as a workaround.
#
# Expects environment variables:
#   GATEWAY_ID          — Gateway identifier
#   CCAPI_RUNTIME_ARN   — CCAPI MCP Server runtime ARN
#   COST_RUNTIME_ARN    — Cost Explorer MCP Server runtime ARN
#   CREDENTIAL_PROVIDER_ARN — OAuth2 credential provider ARN
#   SCOPES              — OAuth scope (e.g. "mcp/invoke")
#   REGION              — AWS region

set -euo pipefail

echo "=== Gateway Target Setup ==="
echo "  Gateway: $GATEWAY_ID"
echo ""

CCAPI_ENDPOINT="https://bedrock-agentcore.${REGION}.amazonaws.com/runtimes/$(python3 -c "import urllib.parse; print(urllib.parse.quote('$CCAPI_RUNTIME_ARN', safe=''))")/invocations?qualifier=DEFAULT"
COST_ENDPOINT="https://bedrock-agentcore.${REGION}.amazonaws.com/runtimes/$(python3 -c "import urllib.parse; print(urllib.parse.quote('$COST_RUNTIME_ARN', safe=''))")/invocations?qualifier=DEFAULT"

CRED_CONFIG="[{\"credentialProviderType\":\"OAUTH\",\"credentialProvider\":{\"oauthCredentialProvider\":{\"providerArn\":\"$CREDENTIAL_PROVIDER_ARN\",\"scopes\":[\"$SCOPES\"],\"grantType\":\"CLIENT_CREDENTIALS\"}}}]"

# Helper: create or update a target
setup_target() {
    local target_name="$1"
    local description="$2"
    local endpoint="$3"

    # Check if target already exists
    local existing_id
    existing_id=$(aws bedrock-agentcore-control list-gateway-targets \
        --gateway-identifier "$GATEWAY_ID" \
        --query "items[?name=='$target_name'].targetId | [0]" \
        --output text 2>/dev/null || echo "None")

    if [ "$existing_id" != "None" ] && [ -n "$existing_id" ]; then
        echo "  Updating target: $target_name ($existing_id)"
        aws bedrock-agentcore-control update-gateway-target \
            --gateway-identifier "$GATEWAY_ID" \
            --target-id "$existing_id" \
            --name "$target_name" \
            --description "$description" \
            --target-configuration "{\"mcp\":{\"mcpServer\":{\"endpoint\":\"$endpoint\"}}}" \
            --credential-provider-configurations "$CRED_CONFIG" \
            --query 'status' --output text 2>&1
    else
        echo "  Creating target: $target_name"
        aws bedrock-agentcore-control create-gateway-target \
            --gateway-identifier "$GATEWAY_ID" \
            --name "$target_name" \
            --description "$description" \
            --target-configuration "{\"mcp\":{\"mcpServer\":{\"endpoint\":\"$endpoint\"}}}" \
            --credential-provider-configurations "$CRED_CONFIG" \
            --query 'targetId' --output text 2>&1
    fi
}

# Create/update CCAPI target
echo "=== CCAPI Target ==="
setup_target \
    "ccapi-mcp-server" \
    "Cloud Control API — infrastructure CRUDL for 1100+ resource types" \
    "$CCAPI_ENDPOINT"

# Wait for CCAPI target sync before creating cost target
echo "  Waiting for target sync..."
sleep 5

# Create/update Cost Explorer target
echo ""
echo "=== Cost Explorer Target ==="
setup_target \
    "cost-explorer-mcp-server" \
    "AWS Cost Explorer — spending analysis and forecasts" \
    "$COST_ENDPOINT"

# Wait for targets to be READY
echo ""
echo "=== Waiting for targets to become READY ==="
for i in $(seq 1 12); do
    STATUSES=$(aws bedrock-agentcore-control list-gateway-targets \
        --gateway-identifier "$GATEWAY_ID" \
        --query 'items[].{name:name,status:status}' \
        --output json 2>/dev/null)

    ALL_READY=true
    for name in "ccapi-mcp-server" "cost-explorer-mcp-server"; do
        STATUS=$(echo "$STATUSES" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for t in data:
    if t['name'] == '$name':
        print(t['status'])
        break
" 2>/dev/null)
        echo "  [$i] $name: $STATUS"
        if [ "$STATUS" != "READY" ]; then ALL_READY=false; fi
    done

    if $ALL_READY; then break; fi
    sleep 5
done

echo ""
echo "=== Target setup complete ==="
