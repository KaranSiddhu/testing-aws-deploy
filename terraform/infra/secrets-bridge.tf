# Secret bridge: Terraform generates ALL secret material and writes it to AWS
# Secrets Manager as complete payloads. External Secrets Operator (in-cluster)
# mirrors each SM secret 1:1 into the k8s Secret the charts expect — no hand-wiring.

# ---------------------------------------------------------------------------
# Generated secret material (TF-owned). Alphanumeric where it lands in a URL.
# ---------------------------------------------------------------------------
resource "random_password" "db" {
  length  = 24
  special = false # alphanumeric → no URL-encoding in the asyncpg DSNs
}
resource "random_password" "app_secret_key" {
  length  = 48
  special = false
}
resource "random_password" "jwt_secret" {
  length  = 48
  special = false
}
resource "random_password" "redis" {
  length  = 32
  special = false
}
resource "random_password" "mcp_token" {
  length  = 32
  special = false
}
resource "random_password" "superadmin" {
  length  = 20
  special = false
}
resource "random_password" "grafana" {
  length  = 20
  special = false
}
# crawl4ai API token — its own value (separate trust boundary from searxng's key).
resource "random_password" "crawl4ai" {
  length  = 32
  special = false
}
# SearXNG server.secret_key — a signing key (NOT a login), injected into searxng's
# settings.yml by the chart's render-config initContainer. Random, never typed.
resource "random_password" "searxng" {
  length  = 48
  special = false
}
# Fernet key = urlsafe-base64 of 32 random bytes (cryptography.fernet format).
resource "random_bytes" "fernet" {
  length = 32
}

locals {
  fernet_key = replace(replace(random_bytes.fernet.base64, "+", "-"), "/", "_")

  db_dsn_pgbouncer = "postgresql+asyncpg://${var.db_username}:${random_password.db.result}@pgbouncer:6432/${var.db_name}?prepared_statement_cache_size=0"
  db_dsn_direct    = "postgresql+asyncpg://${var.db_username}:${random_password.db.result}@${module.rds.db_instance_address}:5432/${var.db_name}?ssl=require"

  pgbouncer_ini      = <<-EOT
    [databases]
    ${var.db_name} = host=${module.rds.db_instance_address} port=5432 dbname=${var.db_name}

    [pgbouncer]
    listen_addr = 0.0.0.0
    listen_port = 6432
    auth_type = plain
    auth_file = /etc/pgbouncer/userlist.txt
    pool_mode = transaction
    max_client_conn = 200
    default_pool_size = 20
    min_pool_size = 5
    reserve_pool_size = 5
    server_tls_sslmode = require
    ignore_startup_parameters = extra_float_digits,options
  EOT
  pgbouncer_userlist = "\"${var.db_username}\" \"${random_password.db.result}\"\n"

  dockerconfigjson = jsonencode({
    auths = {
      "https://index.docker.io/v1/" = {
        username = var.docker_username
        password = var.docker_token
        auth     = base64encode("${var.docker_username}:${var.docker_token}")
      }
    }
  })

  superadmin_password = var.superadmin_password != "" ? var.superadmin_password : random_password.superadmin.result
  grafana_password    = var.grafana_admin_password != "" ? var.grafana_admin_password : random_password.grafana.result

  # name → payload map. Each becomes one SM secret; ESO mirrors keys verbatim.
  sm_secrets = {
    "db-credentials" = {
      host                       = module.rds.db_instance_address
      port                       = "5432"
      username                   = var.db_username
      password                   = random_password.db.result
      database                   = var.db_name
      "connection-string"        = local.db_dsn_pgbouncer
      "direct-connection-string" = local.db_dsn_direct
    }
    "temporal-db-credentials" = {
      host                  = module.rds.db_instance_address
      port                  = "5432"
      username              = var.db_username
      password              = random_password.db.result
      database              = "temporal"
      "visibility-database" = "temporal_visibility"
    }
    "vault-db-credentials" = {
      host     = module.rds.db_instance_address
      port     = "5432"
      username = var.db_username
      password = random_password.db.result
      database = "vault"
    }
    "app-secrets" = {
      "app-secret-key"         = random_password.app_secret_key.result
      "jwt-secret"             = random_password.jwt_secret.result
      "redis-password"         = random_password.redis.result
      "mcp-service-token"      = random_password.mcp_token.result
      "api-key-encryption-key" = local.fernet_key
      "system-email-api-key"   = var.email_api_key
      "superadmin-email"       = var.superadmin_email
      "superadmin-password"    = local.superadmin_password
      "grafana-admin-password" = local.grafana_password # decoupled from superadmin
      "searxng-secret-key"     = random_password.searxng.result
      "crawl4ai-token"         = random_password.crawl4ai.result
    }
    # Non-secret deployment values manifests need but aren't k8s Secrets.
    "deployment-config" = {
      "kms-key-id" = aws_kms_key.vault.key_id
      region       = var.region
      "db-host"    = module.rds.db_instance_address
    }
    "s3-credentials" = {
      endpoint     = "s3.${var.region}.amazonaws.com"
      bucket       = aws_s3_bucket.docs.id
      region       = var.region
      "access-key" = "" # empty → boto3 default chain → Pod Identity (load-bearing)
      "secret-key" = ""
    }
    "pgbouncer-config" = {
      "pgbouncer.ini" = local.pgbouncer_ini
      "userlist.txt"  = local.pgbouncer_userlist
    }
    "registry-credentials" = {
      ".dockerconfigjson" = local.dockerconfigjson
    }
  }
}

# ---------------------------------------------------------------------------
# Secrets Manager objects (recovery_window 0 → destroy is immediate)
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "this" {
  for_each                = local.sm_secrets
  name                    = "${local.name}-${each.key}"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "this" {
  for_each      = local.sm_secrets
  secret_id     = aws_secretsmanager_secret.this[each.key].id
  secret_string = jsonencode(each.value)
}

# Vault root token in its OWN secret so Terraform never rewrites it. The vault-init
# hook PUTs the real token here at runtime; ignore_changes keeps a re-apply from
# blanking it — which would brick the app, because Vault won't re-mint a token against
# an already-initialized Vault. Created empty; recreated empty on a fresh deploy.
resource "aws_secretsmanager_secret" "vault_token" {
  name                    = "${local.name}-vault-token"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "vault_token" {
  secret_id     = aws_secretsmanager_secret.vault_token.id
  secret_string = jsonencode({ "vault-token" = "" })
  lifecycle {
    ignore_changes = [secret_string] # vault-init owns the value after creation
  }
}

# ---------------------------------------------------------------------------
# ESO IAM role → Pod Identity for the external-secrets controller SA.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "eso" {
  name               = "${local.name}-eso"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

data "aws_iam_policy_document" "eso" {
  statement {
    sid       = "ReadDeploymentSecrets"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = ["arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${local.name}-*"]
  }
}

resource "aws_iam_role_policy" "eso" {
  name   = "eso"
  role   = aws_iam_role.eso.id
  policy = data.aws_iam_policy_document.eso.json
}

resource "aws_eks_pod_identity_association" "eso" {
  cluster_name    = module.eks.cluster_name
  namespace       = "external-secrets"
  service_account = "external-secrets" # ESO controller SA (Helm default)
  role_arn        = aws_iam_role.eso.arn
}
