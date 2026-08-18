# Architecture & Decisions

The **why** behind this MagOneAI-on-AWS deployment — the design the `RUNBOOK.md`
assumes and the decisions that are load-bearing. **§7** is the one to never "simplify":
each line there silently breaks the system if removed.

> **Philosophy:** creds → infra reconciles → apps reconcile → maintained forever. One
> concrete deployment, reconciled from Git — destroy and recreate it anytime.

> **Section numbers are referenced from code comments** (e.g. `ARCHITECTURE.md §5`, `§7`)
> — keep them stable when editing.

---

## 1. Principles

1. **Concrete over generated.** What you read in the repo *is* what's deployed.
2. **Boring beats clever.** Flat files, tiny linear scripts, sequencing fixes — no
   bespoke CLI, no local secret managers, no automation papering over ordering.
3. **One home per secret.** Secrets live in `.env` (gitignored) + `.secrets/` (the
   deploy key). Nowhere else. No ad-hoc `export`s.

---

## 2. Identity constants

The single deployment is concrete. These values are baked directly into Terraform and the
ArgoCD app manifests.

| Setting | Value |
|---|---|
| Resource / cluster name | `magoneai` |
| Region | `us-east-1` (the app hardcodes this S3 region — load-bearing, see §7) |
| VPC CIDR / AZs | `10.0.0.0/16` / 3 AZs |
| Subnets | private `/20` (workers) · public `/20` (load balancers) · database `/24` |
| NAT | **one per AZ** (egress HA) |
| EKS / Kubernetes | `1.33` |
| Nodes | `m5.2xlarge` × 3 (min 3 / desired 3 / max 5), **250 GB** root, AL2023 x86_64 |
| Database | RDS PostgreSQL 16, **`db.r6g.xlarge` (4 vCPU / 32 GB)**, 100 GB autoscale→200, single-AZ, backups 7d |
| EKS API endpoint | public but **restricted to `admin_cidrs`** (fail-closed, not `0.0.0.0/0`) |
| Product domain | `app.aidreamlabs.com` — path-based: `/api` `/hub` `/superadmin` `/` |
| Grafana | `grafana.aidreamlabs.com` — own cert + IP allowlist + login |
| Ops tools | Prometheus, Temporal-UI — **internal only** (port-forward) |
| TLS | Let's Encrypt **HTTP-01**, per-host certs, no wildcard, no static IP |

Operator-specific values filled at deploy time (not committed as secrets):
`admin_cidrs` (office/VPN CIDR for the API endpoint + Grafana allowlist), and the
secrets in `.env`.

---

## 3. Ergonomics baked in

| Fix | Implementation |
|---|---|
| **Secrets** | One gitignored `.env` (AWS keys, docker token, superadmin pw, Grafana pw, admin CIDR). Every `bin/*` script does `set -a; [ -f .env ] && . ./.env; set +a`. Fill once, never `export` again. |
| **State bucket** | `bin/init-account.sh`: name derived from account id, created via `aws s3api` (versioning/encryption/public-access-block), idempotent, writes `backend.hcl`. No separate TF stack, no name to invent, no env threading. |
| **Cert / no restart** | **HTTP-01** + **delegate DNS first** (we own the domain): `deploy.sh infra` prints NS → delegate + verify `dig` → `deploy.sh apps`. Cert issues first try. `rollout restart cert-manager` is a documented *fallback only*. |
| **Vault-token crashloop** | `wait-for-secret` initContainer on api/workflow-engine/kb-worker → first deploy converges clean, no rollout-restart. |
| **Grafana password** | Decoupled from superadmin — its own value (`TF_VAR_grafana_admin_password`, random fallback). |

---

## 4. Exposure & TLS design

```
HTTP-01, per-host certs, no wildcard, no static IP (external-dns follows the LB)

app.aidreamlabs.com        → ONE cert, path-based:
  /api → api   /hub → consumer   /superadmin → superadmin   / → web (catch-all, last)

grafana.aidreamlabs.com    → own HTTP-01 cert + IP allowlist (whitelist-source-range) + Grafana login
Prometheus, Temporal-UI    → internal only (kubectl port-forward) — unauthenticated, kept off the internet
```

All ingress/issuer are concrete manifests ArgoCD reconciles. The product's many services
share one cert because they share one host (path routing) — not a wildcard.

---

## 5. Network design & hardening

Three-tier subnets with fail-closed access controls:

- **3-tier subnets** — worker-private / LB-public / DB-private.
- **EKS API endpoint** restricted to `admin_cidrs` (fail-closed, **not** `0.0.0.0/0`).
- **RDS security group** sourced from the **EKS node SG** — cluster-nodes-only and
  identity-based, not a subnet CIDR.
- **NAT one-per-AZ** for egress HA.
- **Load balancer SG** = ingress-nginx service on 80/443 only (LB controller managed).
- **Node-to-node all-ports SG rule** — required for low-port pod services like TEI:80
  (load-bearing, §7).

---

## 6. Resource sizing

| Thing | AWS spec | Note |
|---|---|---|
| Nodes | `m5.2xlarge` × 3, 250 GB | ~8 vCPU / 32 GB per node, ×3 for the full stack |
| DB | `db.r6g.xlarge` (32 GB), PG16, 100 GB autoscale | 32 GB RAM, single-AZ |
| GPU | none | LLM inference is via external provider APIs |
| App images | api/kb-worker/workflow-engine `sha-6a30def`, web/consumer `sha-53e8f42`, superadmin `sha-0c8550c` | pinned platform build |
| Infra images | grafana `12.3.3`, prometheus `v2.51.0`, loki/promtail `2.9.4`, qdrant `v1.14.0`, tei `cpu-1.9`, temporal-ui `2.36.0`, pgbouncer `v1.25.1-p0`, redis `7-alpine`, kube-state-metrics `v2.13.0`, node-exporter `v1.8.2`, metrics-server `v0.7.2` | pinned versions |
| MCP server | pinned by **digest** | digest (not a tag) for reproducibility |

---

## 7. Load-bearing fixes to preserve (do NOT "simplify" these)

Carried forward from hard-won experience. Each is a line that silently breaks the
system if removed:

- **Region `us-east-1`** — the app hardcodes the S3 region.
- **Node-to-node all-ports SG rule** — EKS default only allows ephemeral ports; a
  pod service on a low port (TEI:80) is unreachable cross-node without it.
- **`?ssl=require` in the Postgres DSN** — RDS PG16 forces SSL; asyncpg ignores
  `sslmode=`.
- **Empty MINIO creds** → boto3/aioboto3 default chain → Pod Identity for S3 (no IAM
  user, no app change).
- **PgBouncer** with `statement_cache_size=0` — the app requires it.
- **`force_destroy` on S3 + Route53** (applied *before* relying on it) — else
  teardown fails on non-empty bucket / zone.
- **Vault DB init before Vault** — the `vault_kv_store` table isn't auto-created.
- **ArgoCD bootstrap without `--wait`** — `--wait` hangs against EKS.
- **seed-superadmin as a plain Job** (not a hook) with a retry-until-table-exists
  loop — ordering vs alembic.
- **Teardown order** — drop the ingress ELB (scale ArgoCD to 0 first) → `terraform
  destroy` → sweep orphaned EBS volumes.
- **amd64 nodes** — first-party images are amd64 single-arch.
