output "alb_controller_role_arn" {
  description = <<-EOT
    Goes into the AWS Load Balancer Controller's Helm values:

      serviceAccount:
        annotations:
          eks.amazonaws.com/role-arn: <this>
  EOT
  value       = module.alb_controller_iam.role_arn
}
