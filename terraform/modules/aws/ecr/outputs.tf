output "repository_urls" {
  description = "Map of repository name to its full URL, which is what a chart's image.repository becomes in Phase 7."
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

output "registry_url" {
  description = "The registry host, <account>.dkr.ecr.<region>.amazonaws.com. Used by docker login."
  value       = length(aws_ecr_repository.this) > 0 ? split("/", values(aws_ecr_repository.this)[0].repository_url)[0] : ""
}
