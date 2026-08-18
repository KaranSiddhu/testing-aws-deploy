# The VPC everything else lives in.
#
# Costs nothing. VPCs, subnets, internet gateways and route tables are all free;
# only NAT Gateways, which we deliberately do not create, are billed.

module "vpc" {
  # Local path, not a registry reference. The module is vendored into this repo,
  # like every module in the real deployment repos: a client deployment must be
  # self-contained and frozen, not silently changing when an upstream module
  # publishes a new version.
  source = "../../modules/aws/vpc"

  name       = var.project
  cidr_block = "10.0.0.0/16"

  # Two AZs, which is the minimum EKS and RDS both require.
  #
  # /20 gives 4091 usable addresses each. That sounds excessive for two nodes
  # until you remember the VPC CNI gives every POD a real VPC IP, not just every
  # node. Address exhaustion is a genuine EKS failure mode, and it appears as
  # pods stuck in ContainerCreating with "failed to assign an IP address".
  public_subnets = {
    "us-east-1a" = "10.0.0.0/20"
    "us-east-1b" = "10.0.16.0/20"
  }
}
