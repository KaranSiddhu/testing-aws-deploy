# RDS PostgreSQL 16. Terraform owns the master password (random_password.db in
# secrets-bridge.tf) so it can write complete connection strings to Secrets Manager
# and ESO stays a 1:1 mirror. rds.force_ssl=1 is kept explicit: asyncpg needs ssl in
# the DSN OR PgBouncer in front (load-bearing — ARCHITECTURE.md §7). Data is disposable: no
# deletion protection, skip final snapshot, but automated backups stay ON.

# DB security group: ingress 5432 ONLY from the EKS node security group
# (cluster-nodes-only, identity-based — tighter than a subnet CIDR).
resource "aws_security_group" "rds" {
  name_prefix = "${local.name}-rds-"
  description = "Postgres 5432 from EKS nodes only"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Postgres from EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.10"

  identifier = "${local.name}-pg"

  engine               = "postgres"
  engine_version       = var.db_engine_version
  family               = "postgres${var.db_engine_version}"
  major_engine_version = var.db_engine_version
  instance_class       = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = 200
  storage_encrypted     = true # encrypt data at rest (AWS-managed RDS KMS key)

  db_name  = var.db_name
  username = var.db_username
  port     = 5432

  manage_master_user_password = false
  password                    = random_password.db.result

  multi_az               = false
  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.rds.id]

  backup_retention_period = 7
  deletion_protection     = false
  skip_final_snapshot     = true

  # force_ssl is the PG16 default; kept explicit/visible.
  parameters = [
    { name = "rds.force_ssl", value = "1" }
  ]
}
