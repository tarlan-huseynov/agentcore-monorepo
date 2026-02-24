#!/usr/bin/env bash
# Package app for AgentCore Runtime deployment.
#
# Creates a ZIP with ARM64-compiled dependencies + application code
# suitable for uploading to AgentCore's S3 code bucket.
#
# Usage:
#   ./scripts/package.sh              # Build ZIP only
#   ./scripts/package.sh 3.12         # Specify Python version
#
# Prerequisites: uv, zip

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PYTHON_VERSION="${1:-3.12}"
BUILD_DIR="$PROJECT_ROOT/deployment_package"
ZIP_FILE="$PROJECT_ROOT/deployment_package.zip"

echo "=== AgentCore Bootstrapper Packaging ==="
echo "  Python: $PYTHON_VERSION"
echo ""

# Step 1: Clean previous build
rm -rf "$BUILD_DIR" "$ZIP_FILE"
mkdir -p "$BUILD_DIR"

# Step 2: Install ARM64 dependencies
echo "=== Installing ARM64 dependencies ==="
uv pip compile "$PROJECT_ROOT/pyproject.toml" -o "$BUILD_DIR/_requirements.txt"
uv pip install \
    --python-platform aarch64-manylinux2014 \
    --python-version "$PYTHON_VERSION" \
    --target="$BUILD_DIR" \
    --only-binary=:all: \
    -r "$BUILD_DIR/_requirements.txt"
rm "$BUILD_DIR/_requirements.txt"

# Step 3: Copy application code
echo ""
echo "=== Copying application code ==="
cp -r "$PROJECT_ROOT/app" "$BUILD_DIR/app"

# Step 4: Clean up
echo "=== Cleaning up ==="
find "$BUILD_DIR" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "$BUILD_DIR" -name "*.pyc" -delete 2>/dev/null || true
find "$BUILD_DIR" -name "*.pyo" -delete 2>/dev/null || true
# NOTE: Keep .dist-info — OpenTelemetry needs importlib entry_points.

# Step 5: Set POSIX permissions
echo "=== Setting permissions ==="
find "$BUILD_DIR" -type f -exec chmod 644 {} +
find "$BUILD_DIR" -type d -exec chmod 755 {} +

# Step 6: Create ZIP
echo "=== Creating ZIP ==="
cd "$BUILD_DIR"
zip -rq "$ZIP_FILE" .
cd "$PROJECT_ROOT"

ZIP_SIZE=$(du -h "$ZIP_FILE" | cut -f1)
echo ""
echo "=== Package: $ZIP_FILE ($ZIP_SIZE) ==="
