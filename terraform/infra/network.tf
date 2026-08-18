# =============================================================================
# FILE: terraform/infra/network.tf
#
# WHAT THIS IS
#   The private network everything else lives inside. Builds a VPC with three
#   tiers of subnets across var.az_count availability zones:
#     - private  : the EKS worker nodes. No route in from the internet.
#     - database : RDS. Private, and further isolated from the workers.
#     - public   : load balancers ONLY. The single door into the cluster.
#
# WHY IT IS NEEDED
#   Nothing in AWS is reachable without a network to put it in. Splitting into
#   tiers means a compromised pod cannot be reached directly from the internet,
#   and the database is not sitting in the same subnet as the workloads.
#
# HOW IT GETS BUILT
#   By terraform-aws-modules/vpc, the community-standard VPC module - which is
#   why this file creates zero resources of its own. It fills in a form; the
#   module builds ~30 resources (subnets, route tables, gateways, ACLs).
#
# WHAT YOU MIGHT CHANGE
#   az_count (in terraform.tfvars) and the NAT setting below.
# =============================================================================

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = local.name
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets  = local.private_subnets
  public_subnets   = local.public_subnets
  database_subnets = local.database_subnets

  create_database_subnet_group = true

  # NAT gateway = how pods in the PRIVATE subnets reach the internet (image
  # pulls, LLM APIs, package installs). Nothing outbound works without one.
  #
  # COST DECISION: a NAT gateway is $0.045/hr ($33/mo) EACH, charged even at
  # zero traffic. The upstream default is one per AZ for egress HA, which at
  # az_count=3 is $99/mo of standby capacity.
  #
  # This deployment uses a SINGLE shared NAT: $33/mo instead of $99/mo.
  # Trade-off: if that one AZ fails, pods lose outbound internet until it
  # recovers. For a cluster torn down at the end of each session that is not a
  # risk worth paying for. FLIP BOTH VALUES BACK for anything production.
  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false
  enable_dns_hostnames   = true
  enable_dns_support     = true

  # Tags so ingress-nginx / the LB controller auto-discovers the subnets.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}
