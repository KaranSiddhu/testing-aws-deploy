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
# ?ssl=require, NOT ?sslmode=require.
#
# RDS enforces TLS, so some SSL parameter is mandatory - but which one depends
# on the DRIVER, not on Postgres:
#
#   sslmode=   libpq's parameter. What psql and psycopg2 use, and what every
#              AWS document and Stack Overflow answer shows.
#   ssl=       what asyncpg uses. It does NOT understand sslmode and SQLAlchemy
#              does NOT translate it.
#
# Getting it wrong fails at connect time with a message that mentions neither
# TLS nor RDS:
#
#     TypeError: connect() got an unexpected keyword argument 'sslmode'
#
# This is documented verbatim in magoneai-awnic-deploy/CLAUDE.md - "RDS forces
# SSL and asyncpg ignores sslmode=" - and it was still written wrong here first
# time, which is a fair measure of how easy it is to reach for the form you have
# seen a hundred times.
output "database_url" {
  description = "Complete DATABASE_URL for env.sh. Read with: terraform output -raw database_url"
  value       = "postgresql+asyncpg://${module.rds.username}:${urlencode(module.rds.password)}@${module.rds.address}:${module.rds.port}/${module.rds.db_name}?ssl=require"
  sensitive   = true
}
