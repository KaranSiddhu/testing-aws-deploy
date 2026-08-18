# Variables shared by every layer. Symlinked in, values come from
# common.auto.tfvars, which is also symlinked in.

variable "region" {
  description = "AWS region for every resource."
  type        = string
}

variable "project" {
  description = "Name prefix for every resource, and the Project tag."
  type        = string
}
