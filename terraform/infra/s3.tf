# Docs/object-storage bucket — the app's object store (native S3). The app talks
# standard boto3 with endpoint s3.<region>.amazonaws.com. Kept in us-east-1 (the app
# hardcodes that region). Name is derived from the account id (globally unique).
# force_destroy so teardown can empty it (only takes effect once applied).

resource "aws_s3_bucket" "docs" {
  bucket        = "${var.name_prefix}-documents-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "docs" {
  bucket = aws_s3_bucket.docs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "docs" {
  bucket = aws_s3_bucket.docs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # SSE-S3 — no per-object KMS perms to manage
    }
  }
}

resource "aws_s3_bucket_public_access_block" "docs" {
  bucket                  = aws_s3_bucket.docs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
