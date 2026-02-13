# ---------------------------------------------------------------------------
# S3 bucket for deployment code
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "code" {
  bucket_prefix = "${var.project_name}-code-"
  force_destroy = true # Demo: allow terraform destroy to clean up

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
# Build the deployment package when source changes
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
# Upload the built ZIP to S3
# ---------------------------------------------------------------------------

resource "aws_s3_object" "deployment_package" {
  bucket = aws_s3_bucket.code.id
  key    = "${var.project_name}/deployment_package.zip"
  source = "${path.module}/../deployment_package.zip"

  # Force re-upload whenever the build triggers change
  etag = null_resource.build.id

  depends_on = [null_resource.build]
}
