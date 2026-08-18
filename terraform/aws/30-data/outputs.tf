# These outputs become env.sh in Phase 7. That is the whole handover between
# Terraform and the Kubernetes layer: Terraform knows the endpoint and password,
# k8s-config turns them into a Secret, and the application reads DATABASE_URL
# exactly as it always has.

output "db_address" {
  description = "Database hostname. This is the ONLY application-visible difference from the in-cluster postgres."
  value       = module.rds.address
}

output "db_port" {
  value = module.rds.port
}

output "db_name" {
  value = module.rds.db_name
}

output "db_username" {
  value = module.rds.username
}

output "db_password" {
  description = "Read deliberately with: terraform output -raw db_password"
  value       = module.rds.password
  sensitive   = true
}

output "ecr_registry" {
  description = "Registry host for docker login. Used in Phase 7."
  value       = module.ecr.registry_url
}

output "ecr_repository_urls" {
  description = "Full image repository URLs, which become image.repository in the charts."
  value       = module.ecr.repository_urls
}

# A ready-made DATABASE_URL, so nobody assembles it by hand and gets the
# URL-encoding wrong.
#
# ?sslmode=require is not decoration: RDS enforces TLS, and the connection is
# refused without it. Note AWNIC hit the asyncpg variant of this - asyncpg
# ignores sslmode= and needs ?ssl=require instead. SQLAlchemy translates
# sslmode for asyncpg, so this form works here.
output "database_url" {
  description = "Complete DATABASE_URL for env.sh. Read with: terraform output -raw database_url"
  value       = "postgresql+asyncpg://${module.rds.username}:${urlencode(module.rds.password)}@${module.rds.address}:${module.rds.port}/${module.rds.db_name}?sslmode=require"
  sensitive   = true
}
