variable "name" {
  description = "Name prefix for the node group and its IAM role."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster to join."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets the nodes launch into."
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type. t3.small is ~$0.0208/hour on-demand in us-east-1."
  type        = string
}

variable "node_count" {
  description = "Fixed node count. min, max and desired are all set to this."
  type        = number
}
