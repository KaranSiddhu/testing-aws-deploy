# =============================================================================
# FILE: terraform/infra/terraform.tfvars
#
# WHAT THIS IS
#   The concrete values for THIS deployment. Committed to git - it contains no
#   secrets. Secrets arrive separately from .env as TF_VAR_ environment
#   variables (docker_token, superadmin_password, grafana_admin_password,
#   admin_cidrs, email_api_key).
#
# WHY IT MATTERS
#   This is the file that decides your AWS bill. Node count, node size, and DB
#   class are the three numbers that move it. Read the cost note at the bottom
#   before changing any of them.
#
# SIZED FOR: personal learning. One node, one NAT, small DB, created and
#   destroyed the same day. NOT production sizing - see the notes on each
#   setting for what to raise if this ever needs to serve real traffic.
# =============================================================================

name_prefix = "magoneai"
region      = "us-east-1"

# --- Network ---------------------------------------------------------------
# az_count 2 is the FLOOR: EKS requires subnets in at least two availability
# zones and refuses to create a cluster with one. Production would use 3.
vpc_cidr = "10.0.0.0/16"
az_count = 2

# --- EKS -------------------------------------------------------------------
# t3.2xlarge = 8 vCPU / 32 GiB, x86. x86 is REQUIRED: every MagOneAI image is
# built linux/amd64 only, so Graviton (t4g/m7g) nodes cannot run them.
#
# Why 32 GiB for one node: summed pod requests are ~12 GiB, and three services
# ask for 4 GiB each on their own (workflow-engine, kb-worker, tei-dense).
# Add EKS system pods, ArgoCD, Vault and Temporal and a 16 GiB node will not
# fit the stack.
#
# Why 1 node: the account's "Running On-Demand Standard instances" quota is
# 8 vCPU, and one t3.2xlarge consumes exactly that. max_size 2 is harmless -
# quota is only charged against instances actually running - but a rolling node
# replacement needs 16 vCPU, so it will fail until the pending quota increase
# to 32 is approved.
eks_version         = "1.33"
node_instance_types = ["t3.2xlarge"]
node_disk_size      = 100
node_min_size       = 1
node_desired_size   = 1
node_max_size       = 2

# --- RDS -------------------------------------------------------------------
# One Postgres instance holds all four logical databases (app, temporal,
# temporal_visibility, vault). db.t4g.small = 2 vCPU / 2 GiB on Graviton,
# ample for learning-scale data and ~10% cheaper than the x86 equivalent.
#
# Graviton is fine HERE even though the EKS nodes must stay x86: RDS is a
# managed service running Postgres, not our containers, so the amd64-only
# image constraint does not apply to it.
db_engine_version    = "16"
db_instance_class    = "db.t4g.small"
db_allocated_storage = 20

# --- DNS -------------------------------------------------------------------
# A SUBDOMAIN zone, deliberately. Delegating the apex (karansiddhu.com) would
# hand all DNS for the domain to Route53 and break any existing email or web
# records. Delegating `lab` only means adding 4 NS records at the registrar and
# leaving the rest of the domain untouched.
#
# Hostnames derived from this: app.lab.karansiddhu.com, grafana.lab.karansiddhu.com
# Change the whole domain in one shot with: bin/set-domain.sh <new-zone>
dns_zone = "lab.karansiddhu.com"

# =============================================================================
# COST AT THIS SIZING (us-east-1, on-demand)
#
#   EKS control plane                 $0.100/hr   fixed, charged even when idle
#   1x t3.2xlarge node                $0.333/hr
#   RDS db.t3.small                   $0.036/hr
#   1x NAT gateway                    $0.045/hr   see network.tf
#   Load balancer                     $0.023/hr
#   EBS + RDS storage                 $0.014/hr
#   ------------------------------------------
#   TOTAL                             ~$0.55/hr   -> a 4-hour session ~$2.20
#
# Survives `bin/destroy.sh` and keeps billing: Route53 zone ($0.50/mo), the S3
# state bucket (cents), and ECR image storage (~$1-3/mo).
#
# ALWAYS run bin/destroy.sh when you finish. A cluster left running overnight
# costs ~$13; left for a month, ~$400.
# =============================================================================
