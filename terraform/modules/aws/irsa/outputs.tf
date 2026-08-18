output "role_arn" {
  description = "Role ARN. Goes on the ServiceAccount as the eks.amazonaws.com/role-arn annotation."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  value = aws_iam_role.this.name
}
