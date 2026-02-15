terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket       = "agentcore-demo-tfstate-eu-central-1"
    key          = "agentcore-demo/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true # S3-native locking (Terraform >= 1.10)
  }

  required_providers {
    # AgentCore resources (aws_bedrockagentcore_*) require AWS provider >= 6.17.0
    # Memory resources (aws_bedrockagentcore_memory*) require >= 6.18.0
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.32"
    }
  }
}

provider "aws" {
  default_tags {
    tags = {
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
  name       = var.project_name

  # Bedrock cross-region inference profile prefix derived from deployment region
  _region_prefix_map = {
    "us" = "us"
    "eu" = "eu"
    "ap" = "apac"
  }
  bedrock_region_prefix = local._region_prefix_map[split("-", local.region)[0]]
  bedrock_model_id      = "${local.bedrock_region_prefix}.${var.bedrock_model_id}"
}
