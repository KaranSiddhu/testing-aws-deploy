terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # State in S3 with NATIVE locking (no DynamoDB). bucket + region come from
  # backend.hcl, which bin/init-account.sh writes:
  #   terraform init -backend-config=backend.hcl
  backend "s3" {
    key          = "infra/terraform.tfstate"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}
