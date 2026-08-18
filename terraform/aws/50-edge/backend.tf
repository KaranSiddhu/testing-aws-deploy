terraform {
  backend "s3" {
    bucket       = "dummy-hello-tfstate-660169747695"
    key          = "50-edge/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
