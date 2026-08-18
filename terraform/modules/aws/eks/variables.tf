variable "name" {
  description = "Cluster name, also used as a prefix for its IAM roles."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes minor version. MUST be one on EKS standard support: extended support costs $0.60/hour instead of $0.10."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the control plane's elastic network interfaces. At least two AZs required."
  type        = list(string)
}
