# Outputs = the config/secret bridge surface + the handoff info (NS records).

# --- Cluster ---
output "cluster_name" {
  value = module.eks.cluster_name
}
output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}
output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}

# --- Database ---
output "db_host" {
  value = module.rds.db_instance_address
}
output "db_port" {
  value = module.rds.db_instance_port
}
output "db_name" {
  value = var.db_name
}
output "db_user" {
  value = var.db_username
}

# --- Secret bridge ---
output "secretsmanager_secret_names" {
  description = "SM secrets ESO reads (passwords are TF-owned)."
  value       = [for k, s in aws_secretsmanager_secret.this : s.name]
}
output "eso_role_arn" {
  value = aws_iam_role.eso.arn
}

# --- Object storage ---
output "s3_bucket" {
  value = aws_s3_bucket.docs.id
}
output "s3_region" {
  value = var.region
}
output "s3_endpoint" {
  value = "s3.${var.region}.amazonaws.com"
}

# --- KMS ---
output "kms_key_id" {
  value = aws_kms_key.vault.key_id
}
output "kms_key_arn" {
  value = aws_kms_key.vault.arn
}

# --- Pod Identity role ARNs (reference) ---
output "app_role_arn" {
  value = aws_iam_role.app.arn
}
output "vault_role_arn" {
  value = aws_iam_role.vault.arn
}

# --- Network ---
output "vpc_id" {
  value = module.vpc.vpc_id
}

# --- DNS (the handoff) ---
output "dns_zone_name_servers" {
  description = "Delegate these NS records for var.dns_zone at the registrar (one-time), then deploy apps."
  value       = aws_route53_zone.main.name_servers
}
output "dns_zone_id" {
  value = aws_route53_zone.main.zone_id
}
