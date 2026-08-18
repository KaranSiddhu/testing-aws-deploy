variable "name" {
  description = "Name prefix for the VPC and everything in it."
  type        = string
}

variable "cidr_block" {
  description = "VPC CIDR. /16 gives 65k addresses, far more than needed, but leaves room and costs nothing."
  type        = string
}

variable "public_subnets" {
  description = "Map of availability zone name to subnet CIDR. Keys are AZ names so the mapping is explicit rather than positional."
  type        = map(string)
}
