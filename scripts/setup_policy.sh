#!/usr/bin/env bash
# Create AgentCore Policy Engine and attach safety policy.
#
# Called by Terraform null_resource provisioner.
# Expects: GATEWAY_ID, GATEWAY_ARN as environment variables.
#
# No native Terraform resource exists for AgentCore Policy Engine/Policy
# as of provider ~> 6.32, so we use the AWS CLI directly.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
POLICY_FILE="$PROJECT_ROOT/terraform/policies/safety.cedar"
ENGINE_NAME="${ENGINE_NAME:-agentcore_bootstrapper_policy_engine}"
POLICY_NAME="${POLICY_NAME:-agentcore_bootstrapper_safety_policy}"

echo "=== AgentCore Policy Setup ==="
echo "  Gateway ID:  $GATEWAY_ID"
echo "  Engine name: $ENGINE_NAME"
echo ""

# Step 1: Create policy engine (idempotent — reuse if exists)
echo "=== Creating policy engine ==="
ENGINE_RESPONSE=$(aws bedrock-agentcore-control create-policy-engine \
    --name "$ENGINE_NAME" \
    --description "Safety guardrails for Infrastructure Bootstrapper" \
    2>&1 || true)

if echo "$ENGINE_RESPONSE" | grep -q "policyEngineId"; then
    ENGINE_ID=$(echo "$ENGINE_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['policyEngineId'])")
    ENGINE_ARN=$(echo "$ENGINE_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['policyEngineArn'])")
    echo "  Created: $ENGINE_ID"
else
    # Engine may already exist — list and find it
    echo "  Engine may already exist, looking up..."
    ENGINES=$(aws bedrock-agentcore-control list-policy-engines 2>&1)
    ENGINE_ID=$(echo "$ENGINES" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for e in data.get('policyEngines', []):
    if e.get('name') == '$ENGINE_NAME':
        print(e['policyEngineId'])
        break
")
    ENGINE_ARN=$(echo "$ENGINES" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for e in data.get('policyEngines', []):
    if e.get('name') == '$ENGINE_NAME':
        print(e['policyEngineArn'])
        break
")
    echo "  Found existing: $ENGINE_ID"
fi

if [ -z "$ENGINE_ID" ] || [ -z "$ENGINE_ARN" ]; then
    echo "ERROR: Failed to create or find policy engine"
    exit 1
fi

# Step 2: Read Cedar policy and create policy on the engine
echo ""
echo "=== Creating safety policy ==="
CEDAR_STATEMENT=$(cat "$POLICY_FILE")

# Replace resource placeholder with actual gateway ARN if needed
# (our policy uses bare 'resource' which matches any gateway)

POLICY_RESPONSE=$(aws bedrock-agentcore-control create-policy \
    --policy-engine-id "$ENGINE_ID" \
    --name "$POLICY_NAME" \
    --description "Safety guardrails: restrict resource types for create/update/delete" \
    --validation-mode "FAIL_ON_ANY_FINDINGS" \
    --definition "{\"cedar\": {\"statement\": $(python3 -c "import json; print(json.dumps(open('$POLICY_FILE').read()))")}}" \
    2>&1 || true)

if echo "$POLICY_RESPONSE" | grep -q "policyId"; then
    POLICY_ID=$(echo "$POLICY_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['policyId'])")
    echo "  Created policy: $POLICY_ID"
else
    echo "  Policy may already exist (idempotent)"
fi

# Step 3: Associate policy engine with gateway
echo ""
echo "=== Attaching policy engine to gateway ==="
aws bedrock-agentcore-control update-gateway \
    --gateway-identifier "$GATEWAY_ID" \
    --policy-engine-configuration "{\"mode\": \"ENFORCE\", \"arn\": \"$ENGINE_ARN\"}" \
    2>&1 || echo "  (gateway may already have policy engine attached)"

echo ""
echo "=== Policy setup complete ==="
echo "  Engine: $ENGINE_ID"
echo "  Mode:   ENFORCE"

# Write outputs for Terraform to read
mkdir -p "$PROJECT_ROOT/terraform/.policy_outputs"
echo "$ENGINE_ID" > "$PROJECT_ROOT/terraform/.policy_outputs/engine_id"
echo "$ENGINE_ARN" > "$PROJECT_ROOT/terraform/.policy_outputs/engine_arn"
