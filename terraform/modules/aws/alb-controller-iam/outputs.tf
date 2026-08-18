output "role_arn" {
  description = "Role ARN. Goes into the controller's Helm values as serviceAccount.annotations."
  value       = module.irsa.role_arn
}

output "policy_arn" {
  value = aws_iam_policy.this.arn
}
