output "endpoint" {
  description = "host:port."
  value       = aws_db_instance.this.endpoint
}

output "address" {
  description = "Hostname only, without the port."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Port."
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Initial database name."
  value       = aws_db_instance.this.db_name
}

output "username" {
  description = "Master username."
  value       = aws_db_instance.this.username
}

# sensitive = true keeps this out of plan and apply output, and out of CI logs.
#
# It does NOT encrypt anything. The password is stored in PLAINTEXT in the
# Terraform state file, which is exactly why state lives in a private, encrypted,
# versioned S3 bucket and never in git.
#
# Read it deliberately with:  terraform output -raw db_password
output "password" {
  description = "Generated master password."
  value       = random_password.admin.result
  sensitive   = true
}

output "security_group_id" {
  description = "Security group protecting the database."
  value       = aws_security_group.this.id
}
