# RDS PostgreSQL and the ECR repositories.
#
# ~$0.46/day, almost all of it the database. ECR is free while empty.
# ~8 minutes to apply: RDS is slow to create.

module "rds" {
  source = "../../modules/aws/rds"

  name       = var.project
  vpc_id     = data.terraform_remote_state.network.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.network.outputs.public_subnet_ids

  # Only the EKS cluster's own security group may reach 5432. Nothing else in
  # the VPC, and nothing on the internet.
  allowed_security_group_id = data.terraform_remote_state.cluster.outputs.cluster_security_group_id

  engine_version = "16"
  instance_class = var.db_instance_class

  # Matches the local setup, so DATABASE_URL differs only in its host.
  db_name = "hello"

  # NOT "hello", and not "postgres" or "admin" either - RDS reserves both. Using
  # a different name from the local setup on purpose: it forces the credentials
  # to come from terraform output rather than from memory.
  db_username = "helloadmin"

  backup_retention_days = 1
}

module "ecr" {
  source = "../../modules/aws/ecr"

  # Same names as the Docker Hub repositories, so only the registry host changes
  # when charts are repointed in Phase 7.
  repository_names = [
    "dummy-hello-be",
    "dummy-hello-fe",
  ]
}
