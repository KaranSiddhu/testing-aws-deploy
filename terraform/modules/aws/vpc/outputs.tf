output "vpc_id" {
  description = "VPC id, consumed by the cluster and data layers."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR, used for security group rules."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "All public subnet ids."
  value       = [for s in aws_subnet.public : s.id]
}
