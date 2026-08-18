# All inputs for the single magoneai deployment. Non-secret values live in
# terraform.tfvars (committed). Secrets come from .env via TF_VAR_ (never committed):
# docker_token, superadmin_password, grafana_admin_password, admin_cidrs.

variable "name_prefix" {
  type        = string
  default     = "magoneai"
  description = "Prefix for all resource names; the EKS cluster is named this."
}

variable "region" {
  type    = string
  default = "us-east-1"
  # Load-bearing: the app hardcodes us-east-1 for S3. Keep the docs bucket here
  # unless the app is patched (ARCHITECTURE.md §7).
}

# --- Kubernetes namespace + service accounts (must match the k8s manifests) ---
variable "k8s_namespace" {
  type    = string
  default = "magoneai"
}
variable "app_service_account" {
  type    = string
  default = "magoneai-app"
}
variable "vault_service_account" {
  type    = string
  default = "vault"
}

# --- Network ---
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}
variable "az_count" {
  type    = number
  default = 3
}

# --- Admin access (EKS API endpoint + Grafana IP allowlist) ---
# Comma-separated CIDRs. REQUIRED, no open default — set TF_VAR_admin_cidrs in .env.
# Fail-closed: a bare apply must not expose the API to the world.
variable "admin_cidrs" {
  type        = string
  description = "Comma-separated CIDRs allowed to reach the EKS API endpoint (office/VPN). Via TF_VAR_admin_cidrs."
}

# --- EKS ---
variable "eks_version" {
  type    = string
  default = "1.33"
}
variable "node_instance_types" {
  type    = list(string)
  default = ["m5.2xlarge"]
  # x86_64 REQUIRED: first-party images are amd64 single-arch (ARCHITECTURE.md §7).
}
variable "node_disk_size" {
  type    = number
  default = 250 # large root: the full stack pulls many big ML/MCP images per node
}
variable "node_desired_size" {
  type    = number
  default = 3
}
variable "node_min_size" {
  type    = number
  default = 3
}
variable "node_max_size" {
  type    = number
  default = 5
}

# --- RDS ---
variable "db_engine_version" {
  type    = string
  default = "16"
}
variable "db_instance_class" {
  type    = string
  default = "db.r6g.xlarge" # 4 vCPU / 32 GB — RAM parity with the reference DB
}
variable "db_allocated_storage" {
  type    = number
  default = 100
}
variable "db_name" {
  type    = string
  default = "magoneai_db"
}
variable "db_username" {
  type    = string
  default = "magoneaiadmin"
}

# --- Docker Hub (first-party private images) ---
variable "docker_username" {
  type    = string
  default = "magureme" # login user; image namespace is magureai/*
}
variable "docker_token" {
  type        = string
  sensitive   = true
  description = "Docker Hub pull token (dckr_pat_...). Via TF_VAR_docker_token in .env."
}

# --- Identity / app ---
variable "superadmin_email" {
  type        = string
  description = "Email seeded as the platform superadmin."
}
variable "superadmin_password" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Superadmin login password. Set via TF_VAR_superadmin_password; empty = auto-generate (read via bin/creds.sh)."
}
variable "grafana_admin_password" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Grafana admin password, decoupled from superadmin. Via TF_VAR_grafana_admin_password; empty = auto-generate."
}
variable "email_api_key" {
  type        = string
  sensitive   = true
  default     = "unused"
  description = "Transactional email (Resend) API key. Via TF_VAR_email_api_key; default 'unused' boots the app without sending."
}

# --- DNS / TLS ---
variable "dns_zone" {
  type        = string
  description = "Route53 hosted zone to create (e.g. aidreamlabs.com). Delegate its NS once. Change the whole domain with bin/set-domain.sh. (The ACME email is set in the dns-routing app manifest, not here.)"
}
