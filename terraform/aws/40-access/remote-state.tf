# IRSA roles trust the cluster's OIDC provider, so this layer needs the cluster
# to exist. That is the whole dependency, and it is why 40 comes after 20.
data "terraform_remote_state" "cluster" {
  backend = "s3"
  config = {
    bucket = "dummy-hello-tfstate-660169747695"
    key    = "20-cluster/terraform.tfstate"
    region = "us-east-1"
  }
}
