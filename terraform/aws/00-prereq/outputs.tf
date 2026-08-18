output "state_bucket" {
  description = "Bucket name. Every other layer's backend.tf must match this exactly."
  value       = aws_s3_bucket.state.id
}

output "backend_config" {
  description = "What to put in each downstream layer's backend.tf."
  value       = <<-EOT

    terraform {
      backend "s3" {
        bucket       = "${aws_s3_bucket.state.id}"
        key          = "<layer>/terraform.tfstate"
        region       = "${var.region}"
        encrypt      = true
        use_lockfile = true
      }
    }
  EOT
}
