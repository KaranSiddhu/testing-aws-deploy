# Variables belonging to this layer only. Shared ones are in the symlinked
# common-variables.tf; values for these are in terraform.tfvars.

variable "kubernetes_version" {
  description = <<-EOT
    Kubernetes minor version.

    MUST be on EKS STANDARD support. A version in extended support costs
    $0.60/hour instead of $0.10 - six times the price, for doing nothing.

    Check what is currently on standard support:
      aws eks describe-cluster-versions --region us-east-1 \
        --query 'clusterVersions[?versionStatus==`STANDARD_SUPPORT`].clusterVersion'
  EOT
  type        = string
}

variable "node_instance_type" {
  description = "EC2 instance type for the nodes."
  type        = string
}

variable "node_count" {
  description = "Fixed node count. min, max and desired are all set to this."
  type        = number
}
