variable "name" {
  description = "Name prefix."
  type        = string
}

variable "vpc_id" {
  description = "VPC the security group belongs to."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the DB subnet group. At least two AZs required."
  type        = list(string)
}

variable "allowed_security_group_id" {
  description = "Security group permitted to reach Postgres. The EKS cluster security group."
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL major version. 16 matches the local docker compose and kind setups."
  type        = string
  default     = "16"
}

variable "instance_class" {
  description = "RDS instance class. db.t4g.micro is ~$0.016/hour in us-east-1."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Storage in GiB. 20 is the RDS minimum."
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Initial database name."
  type        = string
}

variable "db_username" {
  description = "Master username. 'admin' and 'postgres' are reserved by RDS."
  type        = string
}

variable "backup_retention_days" {
  description = "Automated backup retention. 1 for practice, 30 in AWNIC production."
  type        = number
  default     = 1
}
