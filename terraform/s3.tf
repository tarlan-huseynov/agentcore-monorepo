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

resource "null_resource" "build_ccapi" {
  triggers = {
    source_hash    = filesha256("${path.module}/../mcp_servers/ccapi_entrypoint.py")
    package_script = filesha256("${path.module}/../scripts/package_mcp.sh")
  }

  provisioner "local-exec" {
    command     = "bash scripts/package_mcp.sh"
    working_dir = "${path.module}/.."
  }
}

resource "null_resource" "build_cost" {
  triggers = {
    source_hash    = filesha256("${path.module}/../mcp_servers/cost_entrypoint.py")
    package_script = filesha256("${path.module}/../scripts/package_mcp.sh")
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
  bucket = aws_s3_bucket.code.id
  key    = "${var.project_name}/deployment_package.zip"
  source = "${path.module}/../deployment_package.zip"

  # Force re-upload whenever the build triggers change
  etag = null_resource.build.id

  depends_on = [null_resource.build]
}

resource "aws_s3_object" "ccapi_package" {
  bucket = aws_s3_bucket.code.id
  key    = "${var.project_name}/mcp_ccapi_package.zip"
  source = "${path.module}/../mcp_ccapi_package.zip"

  etag = null_resource.build_ccapi.id

  depends_on = [null_resource.build_ccapi]
}

resource "aws_s3_object" "cost_package" {
  bucket = aws_s3_bucket.code.id
  key    = "${var.project_name}/mcp_cost_package.zip"
  source = "${path.module}/../mcp_cost_package.zip"

  etag = null_resource.build_cost.id

  depends_on = [null_resource.build_cost]
}
