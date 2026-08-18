output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Consumed by 30-data, so only the cluster can reach the database."
  value       = module.eks.cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "Consumed in Phase 7 by IRSA roles."
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  value = module.eks.oidc_provider_url
}

output "kubeconfig_command" {
  description = "Run this to point kubectl at the cluster."
  value       = module.eks.kubeconfig_command
}
