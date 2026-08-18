data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  name = var.name_prefix

  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # 3-tier subnets carved from the VPC CIDR:
  #   private workers (/20), public load balancers (/20), private database (/24).
  private_subnets  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets   = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i + 8)]
  database_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 240)]

  admin_cidrs = split(",", var.admin_cidrs)

  tags = {
    "magoneai.io/stack" = "infra"
    "managed-by"        = "terraform"
  }
}
