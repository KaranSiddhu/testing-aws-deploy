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

# A MAP, not a list, and the reason is a real Terraform constraint.
#
# for_each keys must be known at PLAN time. A list of ARNs where an element is
# `aws_iam_policy.something.arn` cannot satisfy that: the ARN does not exist
# until apply, so Terraform cannot work out the set members and fails with:
#
#   Error: Invalid for_each argument
#   The "for_each" set includes values derived from resource attributes that
#   cannot be determined until apply
#
# With a map, the KEY is a static label you choose and only the VALUE is
# unknown - which Terraform is perfectly happy with.
#
# It also gives resources stable addresses. With a list and `count`, inserting
# an entry at the front renumbers everything after it, and Terraform proposes
# destroying and recreating attachments that did not change.
variable "policy_arns" {
  description = "Policies to attach, as {static-label = policy-arn}. Keys must be literals, values may be computed."
  type        = map(string)
  default     = {}
}
