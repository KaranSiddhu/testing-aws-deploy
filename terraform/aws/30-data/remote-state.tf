# This layer reads BOTH upstream layers: the network for its subnets, and the
# cluster for the security group that is allowed to reach the database.
#
# That second dependency is why 30-data comes after 20-cluster even though a
# database conceptually has nothing to do with Kubernetes. The ordering follows
# the data, not the org chart.

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "dummy-hello-tfstate-660169747695"
    key    = "10-network/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "cluster" {
  backend = "s3"
  config = {
    bucket = "dummy-hello-tfstate-660169747695"
    key    = "20-cluster/terraform.tfstate"
    region = "us-east-1"
  }
}
