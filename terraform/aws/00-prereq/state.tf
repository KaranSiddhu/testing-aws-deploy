# The S3 bucket that holds every other layer's state.
#
# THE BOOTSTRAP PARADOX: Terraform stores state remotely, but something has to
# create the bucket first, and it cannot store its own state in a bucket that
# does not exist yet.
#
# So this layer alone uses a LOCAL backend - its terraform.tfstate is a file on
# your disk. Every other layer uses the S3 backend this creates.
#
# That local file is gitignored. Losing it is survivable: nothing here holds
# secrets, and `terraform import` can adopt the bucket again. Losing a state
# file with real infrastructure in it is a much worse day, which is exactly why
# the other layers do not keep theirs locally.
#
# AWNIC's README says the same thing in one line:
#   "00-prereq  state bucket. LOCAL backend - it creates the remote one"

locals {
  # S3 bucket names are globally unique across ALL of AWS, not just your
  # account, so "dummy-hello-tfstate" is almost certainly taken. Appending the
  # account id makes it unique without leaking anything: account ids are not
  # secret and appear in every ARN you will ever paste.
  bucket_name = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name

  # Practice only. In production this is true, so a stray `terraform destroy`
  # cannot delete the bucket holding the state of everything else you own.
  force_destroy = true

  tags = { Name = local.bucket_name }
}

# Versioning is the single most valuable setting here.
#
# State corruption happens: an interrupted apply, two people applying at once, a
# bad `state rm`. With versioning you restore yesterday's object and carry on.
# Without it, you reconstruct reality by hand from the AWS console.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# State files contain every value Terraform manages, in PLAINTEXT, including the
# RDS password. Encryption at rest is not optional.
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Belt and braces. Buckets are private by default now, but this makes it
# impossible to make this one public by accident later.
resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# NOTE: no DynamoDB table.
#
# Older guides tell you to create one for state locking. Terraform 1.11+ locks
# natively in S3 with `use_lockfile = true` in the backend block, so the table is
# obsolete: one less resource, one less thing to pay for, one less thing to
# forget to destroy.
