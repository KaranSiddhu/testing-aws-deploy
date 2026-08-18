output "node_role_arn" {
  description = "IAM role the nodes assume."
  value       = aws_iam_role.node.arn
}

output "node_group_name" {
  description = "Node group name."
  value       = aws_eks_node_group.this.node_group_name
}
