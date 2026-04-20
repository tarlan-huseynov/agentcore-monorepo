#!/usr/bin/env bash
# Create AgentCore Policy Engine and attach safety policy.
#
# Called by Terraform null_resource provisioner.
# Expects: GATEWAY_ID, GATEWAY_ARN as environment variables.
#
# No native Terraform resource exists for AgentCore Policy Engine/Policy
# as of provider ~> 6.32, so we use the AWS CLI directly.
#
# The Cedar policy file uses bare `resource` for readability. This script
# replaces it with `resource == AgentCore::Gateway::"<gateway-arn>"` as
# required by the API, and splits multi-statement files into one policy
# per permit/forbid block.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
POLICY_FILE="$PROJECT_ROOT/terraform/policies/safety.cedar"
ENGINE_NAME="${ENGINE_NAME:-agentcore_bootstrapper_policy_engine}"
POLICY_PREFIX="${POLICY_NAME:-agentcore_bootstrapper_safety}"

echo "=== AgentCore Policy Setup ==="
echo "  Gateway ID:  $GATEWAY_ID"
echo "  Gateway ARN: $GATEWAY_ARN"
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

# Step 2: Delete existing policies on the engine (idempotent re-create)
echo ""
echo "=== Cleaning existing policies ==="
EXISTING=$(aws bedrock-agentcore-control list-policies \
    --policy-engine-id "$ENGINE_ID" --output json 2>&1)

echo "$EXISTING" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for p in data.get('policies', []):
    print(p['policyId'])
" 2>/dev/null | while read -r pid; do
    echo "  Deleting: $pid"
    aws bedrock-agentcore-control delete-policy \
        --policy-engine-id "$ENGINE_ID" \
        --policy-id "$pid" >/dev/null 2>&1 || true
done

# Wait for deletions to actually propagate (delete-policy is eventually consistent)
echo "  Waiting for deletions to propagate..."
for i in $(seq 1 30); do
    REMAINING=$(aws bedrock-agentcore-control list-policies \
        --policy-engine-id "$ENGINE_ID" \
        --query 'length(policies)' --output text 2>/dev/null || echo "-1")
    if [ "$REMAINING" = "0" ]; then
        echo "  All policies deleted"
        break
    fi
    if [ "$i" = "30" ]; then
        echo "  WARNING: $REMAINING policies still present after 60s — proceeding anyway"
    fi
    sleep 2
done

# Step 3: Split Cedar file into individual statements and create each.
# The API requires one permit/forbid per policy, and the resource must be
# scoped to a specific Gateway ARN (not bare `resource`).
echo ""
echo "=== Creating safety policies ==="

python3 - "$POLICY_FILE" "$GATEWAY_ARN" "$ENGINE_ID" "$POLICY_PREFIX" << 'PYEOF'
import re, json, subprocess, sys, time

policy_file, gateway_arn, engine_id, prefix = sys.argv[1:5]

with open(policy_file) as f:
    content = f.read()

# Remove comments
content = re.sub(r'//[^\n]*\n', '\n', content)

# Split into individual permit/forbid blocks
blocks = re.findall(r'((?:permit|forbid)\s*\(.*?\)\s*(?:when\s*\{.*?\})?\s*;)', content, re.DOTALL)

if not blocks:
    print("ERROR: No permit/forbid blocks found in Cedar file", file=sys.stderr)
    sys.exit(1)

names = [
    ("ccapi_ro", "CCAPI read-only tools"),
    ("ccapi_cu", "CCAPI create/update safe types"),
    ("ccapi_cub", "CCAPI bundled create workflow (prepare/confirm)"),
    ("ccapi_del", "CCAPI delete restricted types"),
    ("ccapi_delb", "CCAPI bundled delete workflow (prepare/confirm)"),
    ("cost_all", "Cost Explorer all tools"),
]

for i, (block, (name, desc)) in enumerate(zip(blocks, names)):
    block = block.strip()

    # Replace bare `resource` with scoped Gateway resource.
    # Match standalone `resource` at end of permit args (not `resourceType`).
    block = re.sub(
        r',\s*resource\s*\)',
        f',\n    resource == AgentCore::Gateway::"{gateway_arn}"\n)',
        block
    )

    policy_name = f"{prefix}_{name}"
    definition = json.dumps({"cedar": {"statement": block}})

    print(f"  Creating: {policy_name}")
    result = subprocess.run(
        ["aws", "bedrock-agentcore-control", "create-policy",
         "--policy-engine-id", engine_id,
         "--name", policy_name,
         "--description", desc,
         "--validation-mode", "FAIL_ON_ANY_FINDINGS",
         "--definition", definition,
         "--query", "policyId", "--output", "text"],
        capture_output=True, text=True
    )
    if result.returncode == 0:
        print(f"    OK: {result.stdout.strip()}")
    else:
        err = result.stderr.strip()
        print(f"    ERROR: {err[:200]}", file=sys.stderr)
        sys.exit(1)

    time.sleep(1)

print(f"\n  Created {len(blocks)} policies")
PYEOF

# Step 4: Associate policy engine with gateway
echo ""
echo "=== Attaching policy engine to gateway ==="
GW_DATA=$(aws bedrock-agentcore-control get-gateway \
    --gateway-identifier "$GATEWAY_ID" \
    --output json 2>&1)

GW_NAME=$(echo "$GW_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])")
GW_ROLE=$(echo "$GW_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin)['roleArn'])")
GW_PROTO=$(echo "$GW_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin)['protocolType'])")
GW_AUTH=$(echo "$GW_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin)['authorizerType'])")

# 2 Modes available: LOG_ONLY and ENFORCE
# LOG_ONLY: Cedar evaluates and logs decisions but doesn't block
# ENFORCE: Cedar evaluates and blocks if any policy is violated
# Default is LOG_ONLY
# We want to enforce the policies, so we set the mode to ENFORCE
# This is the default mode, so we don't need to set it
# We can set it to LOG_ONLY if we want to test the policies without blocking
# We can set it to ENFORCE if we want to enforce the policies
# We can set it to LOG_ONLY if we want to test the policies without blocking
aws bedrock-agentcore-control update-gateway \
    --gateway-identifier "$GATEWAY_ID" \
    --name "$GW_NAME" \
    --role-arn "$GW_ROLE" \
    --protocol-type "$GW_PROTO" \
    --authorizer-type "$GW_AUTH" \
    --policy-engine-configuration "{\"mode\": \"ENFORCE\", \"arn\": \"$ENGINE_ARN\"}" \
    --query 'policyEngineConfiguration' --output json \
    2>&1 || echo "  (gateway may already have policy engine attached)"

# Wait for gateway to become READY
echo "  Waiting for gateway..."
for i in $(seq 1 12); do
    STATUS=$(aws bedrock-agentcore-control get-gateway \
        --gateway-identifier "$GATEWAY_ID" \
        --query 'status' --output text 2>/dev/null)
    if [ "$STATUS" = "READY" ]; then
        echo "  Gateway READY"
        break
    fi
    sleep 5
done

echo ""
echo "=== Policy setup complete ==="
echo "  Engine: $ENGINE_ID"
echo "  Mode:   LOG_ONLY"

# Write outputs for Terraform to read
mkdir -p "$PROJECT_ROOT/terraform/.policy_outputs"
echo "$ENGINE_ID" > "$PROJECT_ROOT/terraform/.policy_outputs/engine_id"
echo "$ENGINE_ARN" > "$PROJECT_ROOT/terraform/.policy_outputs/engine_arn"
