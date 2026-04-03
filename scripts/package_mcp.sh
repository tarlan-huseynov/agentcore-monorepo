#!/usr/bin/env bash
# Package MCP servers for AgentCore Runtime deployment.
#
# Creates two ZIPs with ARM64-compiled dependencies:
#   mcp_ccapi_package.zip      — Cloud Control API MCP Server
#   mcp_cost_package.zip       — Cost Explorer MCP Server
#
# Usage:
#   ./scripts/package_mcp.sh              # Build both ZIPs
#   ./scripts/package_mcp.sh 3.12         # Specify Python version
#
# Prerequisites: uv, zip

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PYTHON_VERSION="${1:-3.12}"
ARTIFACTS_DIR="$PROJECT_ROOT/.artifacts"

mkdir -p "$ARTIFACTS_DIR"

package_mcp_server() {
    local name="$1"       # e.g. "ccapi" or "cost"
    local pip_pkg="$2"    # e.g. "awslabs.ccapi-mcp-server"
    local entrypoint="$3" # e.g. "ccapi_entrypoint.py"

    local build_dir="$ARTIFACTS_DIR/mcp_${name}_package"
    local zip_file="$ARTIFACTS_DIR/mcp_${name}_package.zip"

    echo "=== Packaging MCP Server: $name ==="
    echo "  Package: $pip_pkg"
    echo "  Python:  $PYTHON_VERSION"
    echo ""

    # Clean previous build
    rm -rf "$build_dir" "$zip_file"
    mkdir -p "$build_dir"

    # Install ARM64 dependencies
    echo "  Installing ARM64 dependencies..."
    uv pip install \
        --python-platform aarch64-manylinux2014 \
        --python-version "$PYTHON_VERSION" \
        --target="$build_dir" \
        --only-binary=:all: \
        "$pip_pkg"

    # Copy entry point and shared modules
    echo "  Copying entry point: $entrypoint"
    cp "$PROJECT_ROOT/mcp_servers/$entrypoint" "$build_dir/"
    for shared in "$PROJECT_ROOT/mcp_servers/_"*.py; do
        [ -f "$shared" ] && cp "$shared" "$build_dir/"
    done

    # Apply patches: copy any override files from mcp_servers/patches/<name>/
    # over the pip-installed versions to fix AgentCore compatibility issues.
    local patches_dir="$PROJECT_ROOT/mcp_servers/patches/$name"
    if [ -d "$patches_dir" ]; then
        echo "  Applying patches from $patches_dir..."
        cp -r "$patches_dir/." "$build_dir/"
    fi

    # Clean up
    find "$build_dir" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    find "$build_dir" -name "*.pyc" -delete 2>/dev/null || true
    find "$build_dir" -name "*.pyo" -delete 2>/dev/null || true

    # Set POSIX permissions
    find "$build_dir" -type f -exec chmod 644 {} +
    find "$build_dir" -type d -exec chmod 755 {} +

    # Create ZIP
    echo "  Creating ZIP..."
    cd "$build_dir"
    zip -rq "$zip_file" .
    cd "$PROJECT_ROOT"

    local zip_size
    zip_size=$(du -h "$zip_file" | cut -f1)
    echo "  Package: $zip_file ($zip_size)"
    echo ""
}

# Package CCAPI MCP Server
package_mcp_server "ccapi" "awslabs.ccapi-mcp-server" "ccapi_entrypoint.py"

# Package Cost Explorer MCP Server
package_mcp_server "cost" "awslabs.cost-explorer-mcp-server" "cost_entrypoint.py"

echo "=== All MCP packages built ==="
