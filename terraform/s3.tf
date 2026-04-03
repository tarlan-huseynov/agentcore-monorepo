# ---------------------------------------------------------------------------
# S3 bucket for deployment code
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "code" {
  bucket_prefix = "${var.project_name}-code-"
  force_destroy = true # Allow terraform destroy to clean up

  tags = { Project = var.project_name }
}

resource "aws_s3_bucket_public_access_block" "code" {
  bucket = aws_s3_bucket.code.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# Build the agent deployment package when source changes
# ---------------------------------------------------------------------------

resource "null_resource" "build" {
  triggers = {
    # Re-build whenever any Python source file changes
    source_hash = sha256(join("", [
      for f in sort(fileset("${path.module}/../app", "**/*.py")) :
      filesha256("${path.module}/../app/${f}")
    ]))
    package_script = filesha256("${path.module}/../scripts/package.sh")
    pyproject      = filesha256("${path.module}/../pyproject.toml")
  }

  provisioner "local-exec" {
    command     = "bash scripts/package.sh"
    working_dir = "${path.module}/.."
  }
}

# ---------------------------------------------------------------------------
# Build MCP server packages when entry points change
# ---------------------------------------------------------------------------

resource "null_resource" "build_mcp" {
  triggers = {
    ccapi_hash = filesha256("${path.module}/../mcp_servers/ccapi_entrypoint.py")
    cost_hash      = filesha256("${path.module}/../mcp_servers/cost_entrypoint.py")
    package_script = filesha256("${path.module}/../scripts/package_mcp.sh")
    # Re-build CCAPI package when any patch file changes (patches override pip-installed files)
    ccapi_patches_hash = sha256(join("", [
      for f in sort(fileset("${path.module}/../mcp_servers/patches/ccapi", "**/*.py")) :
      filesha256("${path.module}/../mcp_servers/patches/ccapi/${f}")
    ]))
  }

  provisioner "local-exec" {
    command     = "bash scripts/package_mcp.sh"
    working_dir = "${path.module}/.."
  }
}

# ---------------------------------------------------------------------------
# Upload deployment ZIPs to S3
# ---------------------------------------------------------------------------

resource "aws_s3_object" "deployment_package" {
  bucket      = aws_s3_bucket.code.id
  key         = "${var.project_name}/deployment_package.zip"
  source      = "${path.module}/../.artifacts/deployment_package.zip"
  source_hash = null_resource.build.triggers.source_hash

  depends_on = [null_resource.build]
}

resource "aws_s3_object" "ccapi_package" {
  bucket      = aws_s3_bucket.code.id
  key         = "${var.project_name}/mcp_ccapi_package.zip"
  source      = "${path.module}/../.artifacts/mcp_ccapi_package.zip"
  source_hash = null_resource.build_mcp.triggers.ccapi_hash

  depends_on = [null_resource.build_mcp]
}

resource "aws_s3_object" "cost_package" {
  bucket      = aws_s3_bucket.code.id
  key         = "${var.project_name}/mcp_cost_package.zip"
  source      = "${path.module}/../.artifacts/mcp_cost_package.zip"
  source_hash = null_resource.build_mcp.triggers.cost_hash

  depends_on = [null_resource.build_mcp]
}
