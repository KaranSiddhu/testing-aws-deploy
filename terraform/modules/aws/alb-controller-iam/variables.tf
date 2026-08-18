variable "name" {
  description = "Name prefix."
  type        = string
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN from the cluster layer."
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC issuer URL without https://."
  type        = string
}

variable "namespace" {
  description = "Namespace the controller runs in."
  type        = string
  default     = "kube-system"
}

variable "service_account" {
  description = "ServiceAccount name the controller's chart creates."
  type        = string
  default     = "aws-load-balancer-controller"
}
