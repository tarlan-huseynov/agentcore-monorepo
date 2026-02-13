terraform {
  required_version = ">= 1.10"

  # Uncomment after running: bash bootstrap.sh
  # backend "s3" {
  #   bucket       = "agentcore-demo-tfstate-us-east-1"
  #   key          = "agentcore-demo/terraform.tfstate"
  #   region       = "us-east-1"
  #   encrypt      = true
  #   use_lockfile = true  # S3-native locking, no DynamoDB needed
  # }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.80"
    }
  }
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  name       = var.project_name
}
