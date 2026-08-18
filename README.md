# MagOneAI on AWS - personal learning deployment

A working AWS deployment of the **MagOneAI v2** platform, run as **GitOps**, sized
and priced for one person learning how the deployment works. It targets a personal
AWS account and is created and destroyed the same day rather than left running.

**Not a production deployment.** Several deliberate trade-offs below would be wrong
for anything real. Each one is commented in the file that makes it.

| | |
|---|---|
| Cluster | EKS, `us-east-1`, one `t3.2xlarge` node |
| Domain | `lab.karansiddhu.com` (a delegated **subdomain**, apex untouched) |
| App | `https://app.lab.karansiddhu.com` |
| Grafana | `https://grafana.lab.karansiddhu.com` |
| Running cost | **~$0.55/hr** - a 4-hour session is about $2.20 |

## Start here

| Doc | What it is for |
|---|---|
| **`ARCHITECTURE.md`** | The **why** - how the pieces fit and which decisions are load-bearing. |
| **`RUNBOOK.md`** | The **how** - cold-start deploy, step by step, with a check after each stage. |
| **`terraform/infra/terraform.tfvars`** | The **numbers** - every value that moves the bill lives here, with the cost of each. |

## The four moving parts

```
terraform/infra/     builds the AWS hardware        (VPC, EKS, RDS, S3, KMS, IAM, DNS)
bin/                 the commands you actually run  (deploy, destroy, creds)
k8s/gitops/          one-time setup inside cluster  (namespace, jobs, ArgoCD bootstrap)
k8s/apps/ + charts/  everything that runs, as code  (ArgoCD reconciles these from git)
```

The install order lives in the **filename prefixes** under `k8s/apps/applications/`:
`00` cluster plumbing, `10` secrets wiring, `25` create databases, `30` data services,
`35` Vault, `40-48` Temporal, `50` the MagOneAI apps, `55` seed admin, `60` public URLs.
ArgoCD waits for each group to be healthy before starting the next.

## Deploy

```bash
cp .env.example .env        # fill secrets (gitignored, auto-sourced by every bin/* script)
bin/init-account.sh         # one-time per account: Terraform state bucket
bin/deploy.sh infra         # VPC/EKS/RDS/...; prints the zone nameservers
# delegate the zone's NS at your registrar, then verify:
#   dig +short NS lab.karansiddhu.com @8.8.8.8
bin/deploy.sh apps          # ArgoCD takes over and reconciles the stack from git
```

Then `bin/creds.sh` for the superadmin login.

> **Run `bin/destroy.sh` when you finish.** Left running overnight this costs about
> $13; left for a month, about $400. The whole point of this setup is that it is
> cheap to recreate.

Route53's hosted zone ($0.50/mo), the S3 state bucket (cents) and ECR image storage
survive teardown on purpose - so the next `deploy.sh` does not have to redo DNS
delegation or re-push images.

## How this differs from a production deployment

Each of these is a cost or simplicity trade-off, commented where it is made:

- **One node, not three** (`terraform.tfvars`). Total pod requests are ~12 GiB, which
  fits a single 32 GiB node. No spare capacity, no tolerance for a node failure.
- **One NAT gateway, not one per AZ** (`network.tf`). $33/mo instead of $99/mo.
  If that AZ fails, pods lose outbound internet.
- **Two AZs, not three** (`terraform.tfvars`). Two is the EKS minimum.
- **Small single-AZ RDS** (`db.t4g.small`, 20 GB). No Multi-AZ, no read replica.
- **No MCP servers.** MCPs give agents their tools (web search, email, calendars,
  SQL). Without them the platform runs fine but agents cannot take external
  actions. This also removes SearXNG, which existed only to back web-search.
  Restore by adding back `k8s/mcps/`, `charts/mcp-server/`, `charts/searxng/` and
  their two Application manifests.
- **Root AWS credentials.** A real deployment would use a scoped IAM role.

## Things that will bite you

- **The images are `linux/amd64` only.** Graviton nodes (t4g, m7g, c7g) cannot run
  them. Keep the node type on x86.
- **`admin_cidrs` is your home IP and it rotates.** When your ISP changes it,
  `kubectl` stops responding. Re-check with `curl -s https://checkip.amazonaws.com`
  and re-apply infra.
- **DNS delegation must be live before `deploy.sh apps`.** cert-manager asks
  Let's Encrypt for real certificates; if `lab.karansiddhu.com` does not resolve
  yet, issuance fails and repeated attempts hit rate limits.
- **EC2 vCPU quota.** One `t3.2xlarge` is 8 vCPU. A rolling node replacement needs
  16, because the new node starts before the old one stops.

## Branches

- `main` - the branch ArgoCD reconciles from (`targetRevision: main` in
  `k8s/apps/app-of-apps.yaml`). A merge here deploys to the cluster.

## Origin

Ported from `magoneai-awinc-deploy`, itself a fork of
[`magoneai-aws`](https://github.com/PradumanS/magoneai-aws). Customer-specific
pieces were removed; sizing, domain, registry and NAT topology were changed for
personal use. The application source is the separate `magoneai_v2` repository -
this repo only deploys it.
