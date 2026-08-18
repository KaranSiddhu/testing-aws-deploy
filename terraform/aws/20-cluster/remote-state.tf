# Read the network layer's outputs.
#
# THIS IS THE GLUE BETWEEN LAYERS. It is read-only: this layer can see
# 10-network's outputs and can never modify its resources. That is the whole
# point of splitting the stack up - a bad plan here physically cannot touch the
# VPC, and a bad plan in 10-network cannot touch the database.
#
# It also encodes the ordering. If 10-network has never been applied, this fails
# immediately with a clear error rather than creating something half-wired.
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "dummy-hello-tfstate-660169747695"
    key    = "10-network/terraform.tfstate"
    region = "us-east-1"
  }
}
