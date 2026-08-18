# Remote state in the bucket created by 00-prereq.
#
# Values here CANNOT be variables. Terraform reads the backend block before it
# evaluates anything else, so `bucket = var.something` is a hard error. That is
# why the bucket name is written out in full in each layer.
#
# use_lockfile: native S3 state locking, Terraform 1.11+. Replaces the DynamoDB
# table older guides describe. Two people applying at once now get a clear "lock
# held by ..." instead of racing and corrupting state.
terraform {
  backend "s3" {
    bucket       = "dummy-hello-tfstate-660169747695"
    key          = "10-network/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
