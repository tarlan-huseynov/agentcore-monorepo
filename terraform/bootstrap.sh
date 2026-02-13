#!/bin/bash
#
# Bootstrap Terraform remote state (run once before first `terraform init`).
#
# Creates an S3 bucket for Terraform state with:
#   - Versioning (state history / rollback)
#   - Encryption (AES-256 server-side)
#   - Public access blocked
#
# State locking uses S3-native conditional writes (Terraform >= 1.10).
# No DynamoDB table needed.
#
# Usage:
#   cd terraform
#   bash bootstrap.sh
#
# After running, uncomment the `backend "s3"` block in main.tf and run:
#   terraform init

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

project_name="agentcore-demo"
region="us-east-1"
s3_bucket_name="${project_name}-tfstate-${region}"

# Read AWS profile from terraform.tfvars (if it exists)
if [[ -f "${SCRIPT_DIR}/terraform.tfvars" ]]; then
  profile="$(echo 'var.aws_profile' | terraform -chdir="${SCRIPT_DIR}" console -var-file terraform.tfvars 2>/dev/null | tr -d '"')"
else
  profile=""
fi

profile_flag=""
if [[ -n "$profile" && "$profile" != "null" ]]; then
  profile_flag="--profile ${profile}"
  echo "Using AWS profile: ${profile}"
else
  echo "Using default AWS credentials"
fi

echo ""
echo "=== Bootstrapping Terraform State ==="
echo "  Bucket: ${s3_bucket_name}"
echo "  Region: ${region}"
echo ""

# Create S3 bucket
if [[ "$region" != "us-east-1" ]]; then
  aws s3api create-bucket \
    --bucket "${s3_bucket_name}" \
    --create-bucket-configuration LocationConstraint="${region}" \
    --region "${region}" \
    ${profile_flag}
else
  aws s3api create-bucket \
    --bucket "${s3_bucket_name}" \
    --region "${region}" \
    ${profile_flag}
fi

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket "${s3_bucket_name}" \
  --versioning-configuration Status=Enabled \
  ${profile_flag}

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket "${s3_bucket_name}" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' \
  ${profile_flag}

# Block public access
aws s3api put-public-access-block \
  --bucket "${s3_bucket_name}" \
  --public-access-block-configuration \
  'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true' \
  ${profile_flag}

echo ""
echo "=== Done. Add this backend block to main.tf: ==="
echo ""

cat <<EOF
  backend "s3" {
    bucket       = "${s3_bucket_name}"
    key          = "${project_name}/terraform.tfstate"
    region       = "${region}"
    encrypt      = true
    use_lockfile = true  # S3-native locking (Terraform >= 1.10)
  }
EOF

echo ""
echo "Then run: terraform init"
