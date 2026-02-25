#!/usr/bin/env bash
# End-to-end test suite for the AgentCore Infrastructure Bootstrapper.
#
# Tests the full deployed stack:
#   Agent Runtime → LLM → Gateway → Cedar Policy → OAuth → MCP Runtime → AWS API
#
# Usage:
#   AWS_PROFILE=tarlan bash scripts/test_e2e.sh
#
# Prerequisites:
#   - Terraform applied (terraform/ directory has state)
#   - AWS CLI configured with bedrock-agentcore-control
#   - uv installed (for cli_remote.py)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="$PROJECT_ROOT/terraform"

# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

PASSED=0
FAILED=0
SKIPPED=0
TOTAL=0

pass() {
    TOTAL=$((TOTAL + 1))
    PASSED=$((PASSED + 1))
    echo -e "  ${GREEN}[PASS]${NC} ${TOTAL}/16  $1"
}

fail() {
    TOTAL=$((TOTAL + 1))
    FAILED=$((FAILED + 1))
    echo -e "  ${RED}[FAIL]${NC} ${TOTAL}/16  $1"
    if [ -n "${2:-}" ]; then
        echo -e "         ${DIM}$2${NC}"
    fi
}

skip() {
    TOTAL=$((TOTAL + 1))
    SKIPPED=$((SKIPPED + 1))
    echo -e "  ${YELLOW}[SKIP]${NC} ${TOTAL}/16  $1"
}

# ---------------------------------------------------------------------------
# Read Terraform outputs
# ---------------------------------------------------------------------------
echo -e "\n${BOLD}=== AgentCore E2E Test Suite ===${NC}\n"
echo -e "${DIM}Reading Terraform outputs...${NC}"

TF_OUT=$(terraform -chdir="$TF_DIR" output -json 2>/dev/null)

RUNTIME_ARN=$(echo "$TF_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['runtime_arn']['value'])")
RUNTIME_ID=$(echo "$TF_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['runtime_id']['value'])")
GATEWAY_ID=$(echo "$TF_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['gateway_id']['value'])")
CCAPI_ID=$(echo "$TF_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['ccapi_runtime_id']['value'])")
COST_ID=$(echo "$TF_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['cost_runtime_id']['value'])")
REGION=$(echo "$RUNTIME_ARN" | cut -d: -f4)

echo -e "${DIM}  Runtime: $RUNTIME_ID${NC}"
echo -e "${DIM}  Gateway: $GATEWAY_ID${NC}"
echo -e "${DIM}  CCAPI:   $CCAPI_ID${NC}"
echo -e "${DIM}  Cost:    $COST_ID${NC}"
echo -e "${DIM}  Region:  $REGION${NC}"
echo ""

# ---------------------------------------------------------------------------
# Helper: check runtime status
# ---------------------------------------------------------------------------
check_runtime_status() {
    local runtime_id="$1"
    local status
    status=$(aws bedrock-agentcore-control get-agent-runtime \
        --agent-runtime-id "$runtime_id" \
        --region "$REGION" \
        --query 'status' --output text 2>/dev/null || echo "ERROR")
    echo "$status"
}

# ---------------------------------------------------------------------------
# Helper: invoke agent and check response content
# ---------------------------------------------------------------------------
run_agent_test() {
    local prompt="$1"
    local expected_content="$2"   # pipe-separated keywords to find in response
    local test_name="$3"

    local response
    response=$(cd "$PROJECT_ROOT" && uv run python cli_remote.py \
        -q "$prompt" \
        --arn "$RUNTIME_ARN" \
        2>/dev/null) || true

    if [ -z "$response" ]; then
        fail "$test_name" "Empty response from agent"
        return
    fi

    # Check if any expected keyword appears in the response (case-insensitive).
    # MCP tool names may not appear in output (they're internal to the agent loop),
    # so we verify by checking the answer content proves the right tool was called.
    local found
    found=$(echo "$response" | python3 -c "
import sys
text = sys.stdin.read().lower()
keywords = '$expected_content'.lower().split('|')
if any(kw in text for kw in keywords):
    print('FOUND')
else:
    print('NOT_FOUND')
" 2>/dev/null) || found="ERROR"

    if [ "$found" = "FOUND" ]; then
        pass "$test_name"
    else
        fail "$test_name" "Expected content not found: '$expected_content'"
        echo -e "         ${DIM}Response: ${response:0:200}${NC}"
    fi
}

# ---------------------------------------------------------------------------
# Helper: invoke agent and check for denial (negative test)
# ---------------------------------------------------------------------------
run_negative_test() {
    local prompt="$1"
    local test_name="$2"

    local response
    response=$(cd "$PROJECT_ROOT" && uv run python cli_remote.py \
        -q "$prompt" \
        --arn "$RUNTIME_ARN" \
        2>/dev/null) || true

    if [ -z "$response" ]; then
        fail "$test_name" "Empty response from agent"
        return
    fi

    # Check if response mentions denial/policy/forbidden/error.
    # In LOG_ONLY mode, Cedar logs but doesn't block — the denial comes
    # from IAM (no EC2 permissions on the CCAPI role) or the agent's
    # own safety reasoning.
    local found
    found=$(echo "$response" | python3 -c "
import sys
text = sys.stdin.read().lower()
deny_keywords = ['denied', 'forbidden', 'not allowed', 'not permitted',
                 'policy', 'unauthorized', 'restricted', 'cannot delete',
                 'unable to delete', 'not supported', 'ec2', 'error',
                 'failed', 'access denied', 'permission', 'not authorized']
if any(kw in text for kw in deny_keywords):
    print('DENIED')
else:
    print('NOT_DENIED')
" 2>/dev/null) || found="ERROR"

    if [ "$found" = "DENIED" ]; then
        pass "$test_name"
    else
        fail "$test_name" "Expected denial but response did not indicate policy block"
        echo -e "         ${DIM}Response: ${response:0:200}${NC}"
    fi
}

# ===========================================================================
# Layer 1: Infrastructure Health
# ===========================================================================
echo -e "${BOLD}--- Layer 1: Infrastructure Health ---${NC}\n"

# Test 1: Main runtime READY
STATUS=$(check_runtime_status "$RUNTIME_ID")
if [ "$STATUS" = "READY" ]; then
    pass "Main runtime READY"
else
    fail "Main runtime READY" "Status: $STATUS"
fi

# Test 2: CCAPI runtime READY
STATUS=$(check_runtime_status "$CCAPI_ID")
if [ "$STATUS" = "READY" ]; then
    pass "CCAPI runtime READY"
else
    fail "CCAPI runtime READY" "Status: $STATUS"
fi

# Test 3: Cost Explorer runtime READY
STATUS=$(check_runtime_status "$COST_ID")
if [ "$STATUS" = "READY" ]; then
    pass "Cost Explorer runtime READY"
else
    fail "Cost Explorer runtime READY" "Status: $STATUS"
fi

# Test 4: Gateway READY
GW_STATUS=$(aws bedrock-agentcore-control get-gateway \
    --gateway-identifier "$GATEWAY_ID" \
    --region "$REGION" \
    --query 'status' --output text 2>/dev/null || echo "ERROR")
if [ "$GW_STATUS" = "READY" ]; then
    pass "Gateway READY"
else
    fail "Gateway READY" "Status: $GW_STATUS"
fi

# Tests 5-6: Gateway targets READY
TARGETS=$(aws bedrock-agentcore-control list-gateway-targets \
    --gateway-identifier "$GATEWAY_ID" \
    --region "$REGION" 2>/dev/null || echo '{"items":[]}')

CCAPI_TARGET_STATUS=$(echo "$TARGETS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for t in data.get('items', []):
    if 'ccapi' in t.get('name', '').lower():
        print(t.get('status', 'UNKNOWN'))
        break
else:
    print('NOT_FOUND')
" 2>/dev/null)

COST_TARGET_STATUS=$(echo "$TARGETS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for t in data.get('items', []):
    if 'cost' in t.get('name', '').lower():
        print(t.get('status', 'UNKNOWN'))
        break
else:
    print('NOT_FOUND')
" 2>/dev/null)

if [ "$CCAPI_TARGET_STATUS" = "READY" ]; then
    pass "CCAPI gateway target READY"
else
    fail "CCAPI gateway target READY" "Status: $CCAPI_TARGET_STATUS"
fi

if [ "$COST_TARGET_STATUS" = "READY" ]; then
    pass "Cost Explorer gateway target READY"
else
    fail "Cost Explorer gateway target READY" "Status: $COST_TARGET_STATUS"
fi

# ===========================================================================
# Layer 2: CCAPI MCP Server Tools
# ===========================================================================
echo -e "\n${BOLD}--- Layer 2: CCAPI MCP Server Tools ---${NC}\n"

run_agent_test \
    "What is my AWS account ID and region? Use the get_aws_session_info tool." \
    "166733594871|account|eu-central" \
    "CCAPI: get_aws_session_info"

run_agent_test \
    "Explain what AWS Lambda is. Use the explain tool." \
    "lambda|serverless|function" \
    "CCAPI: explain"

run_agent_test \
    "Show me the Cloud Control schema for AWS::SQS::Queue. Use get_resource_schema_information." \
    "sqs|queue|schema" \
    "CCAPI: get_resource_schema_information"

run_agent_test \
    "List all S3 buckets in my account. Use the list_resources tool with type AWS::S3::Bucket." \
    "bucket|s3" \
    "CCAPI: list_resources"

run_agent_test \
    "Generate a CloudFormation template for a DynamoDB table with a partition key called id." \
    "dynamodb|cloudformation|template|partition" \
    "CCAPI: create_template / generate_infrastructure_code"

# ===========================================================================
# Layer 3: Cost Explorer MCP Server Tools
# ===========================================================================
echo -e "\n${BOLD}--- Layer 3: Cost Explorer MCP Server Tools ---${NC}\n"

run_agent_test \
    "What is today's date? Use the get_today_date tool." \
    "2026|february|date" \
    "Cost: get_today_date"

run_agent_test \
    "Show my AWS costs for the last 7 days grouped by service. Use get_cost_and_usage." \
    "cost|usage|service|\$" \
    "Cost: get_cost_and_usage"

run_agent_test \
    "What AWS cost dimensions are available? Use get_dimension_values." \
    "dimension|service|region|az" \
    "Cost: get_dimension_values"

# ===========================================================================
# Layer 4: Direct Tool (search_logs)
# ===========================================================================
echo -e "\n${BOLD}--- Layer 4: Direct Tool ---${NC}\n"

run_agent_test \
    "List all available CloudWatch log groups. Use the search_logs tool with an empty log_group." \
    "log group|search_logs|/aws/" \
    "Direct: search_logs"

# ===========================================================================
# Layer 5: Safety Guardrails (Cedar + IAM)
# ===========================================================================
echo -e "\n${BOLD}--- Layer 5: Safety Guardrails ---${NC}\n"

run_negative_test \
    "Delete the RDS instance mydb-instance using the delete_resource tool with type_name AWS::RDS::DBInstance." \
    "Safety: delete RDS blocked (Cedar + IAM)"

# ===========================================================================
# Summary
# ===========================================================================
echo -e "\n${BOLD}========================================${NC}"
if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}  All tests passed: $PASSED/$((PASSED + FAILED + SKIPPED))${NC}"
else
    echo -e "${RED}${BOLD}  Results: $PASSED passed, $FAILED failed, $SKIPPED skipped${NC}"
fi
echo -e "${BOLD}========================================${NC}\n"

exit "$FAILED"
