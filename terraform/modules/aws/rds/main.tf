# RDS PostgreSQL.
#
# This replaces the in-cluster postgres StatefulSet. The application does not
# change at all: it reads DATABASE_URL, and only that value differs. That is the
# payoff for keeping all configuration in environment variables since Phase 0.
#
# PRACTICE SIZING. AWNIC runs db.m6g.large, Multi-AZ, 30-day backups and
# deletion protection ON, because it is client production. Every difference
# below is deliberate and would be wrong in production.

resource "random_password" "admin" {
  length = 32
  # RDS rejects / @ " and space in a master password. Restricting the character
  # set here is cheaper than discovering it as an API error after a 6-minute
  # create.
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Which subnets the database may live in. RDS demands at least two AZs even for
# a single-AZ instance, because it wants somewhere to fail over to if Multi-AZ
# is ever enabled.
resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db"
  subnet_ids = var.subnet_ids
  tags       = { Name = "${var.name}-db" }
}

resource "aws_security_group" "this" {
  name        = "${var.name}-rds"
  description = "Postgres access for ${var.name}"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-rds" }
}

# Only the EKS nodes may reach the database, and only on 5432.
#
# Referencing a security group rather than a CIDR is the important part: it
# means "whatever is in that group", so nodes replaced by an upgrade are still
# allowed without any rule changing. A CIDR would also work here but would
# silently permit anything else that happens to be in the VPC.
resource "aws_vpc_security_group_ingress_rule" "from_cluster" {
  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = var.allowed_security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "Postgres from EKS nodes"
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name}-db"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = var.db_name
  username = var.db_username
  password = random_password.admin.result

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]

  # NOT publicly accessible: no public IP, unreachable from the internet even
  # though it sits in a public subnet. "Public subnet" describes the routing;
  # this flag decides whether the instance gets a public address at all.
  #
  # Consequence: you cannot psql into it from your laptop. Reach it from a pod
  # in the cluster, or with `kubectl port-forward` through one.
  publicly_accessible = false

  multi_az = false # production: true. Roughly doubles the cost.

  backup_retention_period = var.backup_retention_days
  skip_final_snapshot     = true  # production: false
  deletion_protection     = false # production: true

  # Minor version upgrades during the maintenance window. Fine here; in
  # production you schedule these deliberately.
  auto_minor_version_upgrade = true

  # Both false for practice. In production, Performance Insights is the first
  # thing you want when the database is slow and nobody knows why.
  performance_insights_enabled = false

  tags = { Name = "${var.name}-db" }
}
