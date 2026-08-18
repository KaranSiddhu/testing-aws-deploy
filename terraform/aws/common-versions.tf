# Shared version pins. Symlinked into every layer.
#
# Pinning matters more here than almost anywhere else: a provider that
# silently upgrades between `plan` and `apply`, or between your machine and a
# colleague's, can propose destroying and recreating real infrastructure.
#
# ~> 6.0 means "any 6.x, never 7.0". Major versions of the AWS provider carry
# breaking changes.
terraform {
  # 1.11+ required for native S3 state locking (use_lockfile), which replaces
  # the DynamoDB table older guides tell you to create.
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }
}
