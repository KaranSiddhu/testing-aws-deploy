variable "name" {
  description = "IAM role name."
  type        = string
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN from the cluster layer."
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC issuer URL without the https:// prefix, as IAM condition keys expect it."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the ServiceAccount allowed to assume this role."
  type        = string
}

variable "service_account" {
  description = "ServiceAccount name allowed to assume this role."
  type        = string
}

variable "policy_arns" {
  description = "Managed or customer policy ARNs to attach."
  type        = list(string)
  default     = []
}
