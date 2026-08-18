# These outputs are the layer's public interface. Downstream layers read them
# through terraform_remote_state, which is what makes the dependency between
# layers explicit and readable instead of a shared global.

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "vpc_cidr" {
  value = module.vpc.vpc_cidr
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}
