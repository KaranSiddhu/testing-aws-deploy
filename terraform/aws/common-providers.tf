# Shared provider configuration. Symlinked into every layer.

provider "aws" {
  region = var.region

  # default_tags applies these to every resource this provider creates, without
  # repeating them on each one.
  #
  # Not cosmetic. These tags are how you answer "what is this thing and can I
  # delete it?" in six months, and how you find everything belonging to this
  # project when the bill arrives. Cost Explorer can group by tag.
  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Repo      = "testing-aws-magure-deploy"
    }
  }
}

# Who am I, and which account is this? Used for the state bucket name (which
# must be globally unique across all of AWS) and for IAM policy documents.
data "aws_caller_identity" "current" {}
