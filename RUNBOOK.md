# Deployment Runbook

Cold-start, step-by-step deploy of the MagOneAI stack on AWS — from credentials to a
live, TLS-secured app — then validation and teardown. Each step has a **✅ Check**.

> **Deploying your own fork?** Do **`CUSTOMIZE.md`** first (a few committed edits), then
> follow this runbook top to bottom — no need to come back.

> **This is one concrete deployment.** Identity is fixed:
> cluster `magoneai`, region `us-east-1`, product at `https://app.lab.karansiddhu.com`,
> Grafana at `https://grafana.lab.karansiddhu.com`, Route53 zone `lab.karansiddhu.com`.
> **To change the domain:** run `bin/set-domain.sh <new-zone>` (rewrites the zone, the
> `app.`/`grafana.` hostnames, the external-dns filter, and this runbook in one shot),
> then commit + push. For your fork, domain, sizing, and other deployment-specific values,
> see **`CUSTOMIZE.md`** (the *why* behind each is in `ARCHITECTURE.md`).
>
> **Secrets live in `.env`** (gitignored) and every `bin/*` script auto-sources it —
> you never `export` by hand.

---

## Phase 0 — Prerequisites

### 0.1 Tools
```bash
terraform version        # OpenTofu >= 1.10
kubectl version --client
helm version        # v3 or v4
aws --version       # AWS CLI v2
git --version
jq --version
```
**✅ Check:** every tool prints a version.

### 0.2 Collect these inputs
| # | What | Where it's used |
|---|------|-----------------|
| 1 | **AWS admin access keys** for the target account | `.env` (`AWS_ACCESS_KEY_ID`/`SECRET`) |
| 2 | **Docker Hub pull token** (`dckr_pat_…`, login user `magureme`) | `.env` → ESO pull secret |
| 3 | **Admin CIDR** (your office/VPN, e.g. `203.0.113.4/32`) | EKS API endpoint lock + Grafana allowlist |
| 4 | **Registrar access** for `lab.karansiddhu.com` | one-time NS delegation |

### 0.3 Create and fill `.env`
`.env` is the single home for all secrets (gitignored; every `bin/*` script auto-sources it).
Copy the template first:
```bash
cp .env.example .env
```
Then edit `.env` and set:
- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_REGION` — target account admin
- `TF_VAR_docker_token` — Docker Hub pull token
- `TF_VAR_admin_cidrs` — your office/VPN CIDR
- `TF_VAR_superadmin_email` (+ optional `TF_VAR_superadmin_password`, `TF_VAR_grafana_admin_password`)

Load it and verify AWS reaches the **target** account:
```bash
set -a; . ./.env; set +a
aws sts get-caller-identity
echo "${TF_VAR_docker_token:0:9}"      # → dckr_pat_
```
**✅ Check:** `get-caller-identity` returns the **target** account id; the token prints `dckr_pat_`.

### 0.4 GitHub repo + deploy key (ArgoCD reads from git)
```bash
gh repo create PradumanS/magoneai-aws --private --source . --remote origin --push  # skip if it already exists
mkdir -p .secrets
ssh-keygen -t ed25519 -N "" -f .secrets/argocd_deploy_key -C "argocd-magoneai"
gh repo deploy-key add .secrets/argocd_deploy_key.pub --title "argocd-magoneai"   # read-only
```
> The repo name above is the reference deployment's. For your own, create the repo you set
> in CUSTOMIZE §1 — it must match the `repoURL` baked into the manifests.

**✅ Check:** `gh repo deploy-key list` shows the key as read-only; `.secrets/` is gitignored.

---

## Phase 1 — Account bootstrap (one-time per account)
```bash
bin/init-account.sh
```
Derives the state bucket name from the account id, creates it (idempotent), and writes
`terraform/infra/backend.hcl`.
**✅ Check:** prints `Wrote terraform/infra/backend.hcl … bucket=magoneai-tf-state-<account>`.

---

## Phase 2 — Provision infrastructure
```bash
bin/deploy.sh infra
```
Runs `terraform init`+`apply`: VPC (3-tier subnets, NAT per-AZ), EKS 1.33 (API locked to your
`admin_cidrs`), RDS PG16 `db.r6g.xlarge`, S3, KMS, IAM Pod Identity, the secret bridge to
Secrets Manager, and the Route53 zone. Takes ~15–20 min (EKS + RDS are slow). At the end it
**prints the zone nameservers**.
**✅ Check:** ends with `Apply complete!` and lists 4 AWS nameservers. `kubectl get nodes`
(after `aws eks update-kubeconfig --name magoneai --region us-east-1`) shows 3 Ready, amd64.

---

## Phase 3 — Delegate DNS (the one human step — do it BEFORE apps)

HTTP-01 issues the cert against a publicly-resolvable hostname, so the zone must be live in
public DNS **before** the apps deploy. You own `lab.karansiddhu.com`, so do it now.

At the registrar (Squarespace) for `lab.karansiddhu.com`, set the domain's **NS records** to the
4 nameservers from Phase 2.
**✅ Check (propagation: minutes):**
```bash
dig +short NS lab.karansiddhu.com @8.8.8.8     # returns the 4 AWS nameservers
```
> Query `@8.8.8.8` to avoid a stale local cache.

---

## Phase 4 — Deploy the apps (GitOps)
```bash
bin/deploy.sh apps          # installs ArgoCD, applies the app-of-apps
kubectl get applications -n argocd -w
```
ArgoCD reconciles the whole stack from git in sync-wave order: external-secrets → eso-config
→ foundation → data stores + vault → temporal → app + jobs → DNS/TLS. The **mcps
ApplicationSet** spawns 11 `mcp-*` child apps a few seconds after it syncs (~45 workloads total).

> **Expected first-deploy convergence (not failures):** the `wait-for-vault-token`
> initContainer holds api/workflow-engine/kb-worker until the `vault-init` Job seeds the
> root token and ESO syncs it (~1 min), so they sit in `Init` briefly, then start. No
> crash-loop, no manual restart.

**✅ Check:** every Application is `Synced` + `Healthy`; `kubectl get pods -n magoneai` shows
app pods Running.

---

## Phase 5 — TLS & reachability
```bash
kubectl get certificate -n magoneai          # magoneai-tls → READY=True
curl -sS https://app.lab.karansiddhu.com/health  # HTTP 200
```
external-dns creates `app.lab.karansiddhu.com` → the ingress LB; cert-manager completes HTTP-01 on
the first try (DNS is already delegated).
**✅ Check:** `https://app.lab.karansiddhu.com` loads with a valid lock.
> If the cert is briefly `Ready=False` right after deploy (LB/A-record still settling), it
> resolves on its own. Only as a last resort: `kubectl -n cert-manager rollout restart deploy/cert-manager`.

---

## Phase 6 — App initialization (superadmin, MFA, org)

App-level steps (not infra). Get the credentials:
```bash
bin/creds.sh        # prints superadmin email+password, Grafana password, NS records
```
1. Open **`https://app.lab.karansiddhu.com/superadmin`**, log in with the superadmin credentials,
   complete **MFA enrollment** (TOTP) when prompted. (The main app shows "No Organizations"
   for a superuser — use the portal.)
2. In the portal, create the **organization** and its **owner** user.
3. The owner logs into **`https://app.lab.karansiddhu.com`** and sees their org.
4. Add the **LLM provider API key** (in-app) for RAG/agents.

**✅ Check (end-to-end):** create a KB, upload a PDF → it ingests (extract → chunk → embed →
indexed in Qdrant) and is queryable. Exercises S3 (Pod Identity), TEI, Qdrant, Temporal.

---

## Phase 7 — Validate the full stack

| What | How |
|---|---|
| **MCPs** | each `mcp-*` Application Healthy; exercise **file-generation** (writes to S3 via Pod Identity → no AccessDenied) |
| **SearXNG** | from a curl pod: `wget -qO- 'http://searxng:8080/search?q=test&format=json'` returns results |
| **Prometheus** | `kubectl -n magoneai port-forward svc/prometheus 9090:9090` → `/targets` all UP |
| **Temporal-UI** | `kubectl -n magoneai port-forward svc/temporal-ui 8080:8080` → workflows/namespaces visible |
| **Grafana** | see below |

### Expose Grafana (optional — IP allowlist)
Grafana is internal by default. To expose it at `https://grafana.lab.karansiddhu.com`:
```bash
# edit k8s/apps/applications/50-grafana.yaml → ingress.allowedCidrs: "<your-admin-cidr>"
git commit -am "expose grafana to admin CIDR" && git push
```
ArgoCD creates the ingress + cert; reach it from an allowlisted IP, log in with the Grafana
password from `bin/creds.sh`. Leave `allowedCidrs: ""` to keep it internal:
`kubectl -n magoneai port-forward svc/grafana 3000:3000`.

---

## Phase 8 — Teardown
```bash
bin/destroy.sh
```
Quiesces ArgoCD/external-dns, drops the ingress ELB, `terraform destroy` (force_destroy clears the
Route53 records), sweeps orphaned EBS volumes. Then remove the registrar NS delegation if
desired (harmless if left).
**✅ Check:** `terraform` reports destroy complete; no leftover EBS volumes; the S3 docs bucket is gone.

> ⚠️ **Destroy is instantly unrecoverable, by design.** Secrets Manager secrets use
> `recovery_window_in_days = 0`, and `force_destroy` / `deletion_protection = false` are set
> on S3 and RDS. There is no soft-delete window and no final RDS snapshot — `bin/destroy.sh`
> wipes everything immediately. This is intentional (data is disposable; a deployment is
> reconstructable from `.env` + git), but make sure that's what you want before running it.

---

## Appendix — Common stalls
- **Cert `Ready=False`** → DNS not delegated/propagated yet, or LB still settling; resolves on
  its own (last resort: restart cert-manager).
- **api/worker/kb-worker in `Init`** → expected: waiting for the vault-token to be seeded. Clears
  in ~1 min.
- **`terraform destroy` fails on the VPC** → ingress ELB still present; `bin/destroy.sh` handles ordering.
- **Embeddings/RAG hang** → the node-to-node all-ports SG rule (in `eks.tf`) must be present.

## Appendix — Quick recap of inputs
1. AWS admin access keys (in `.env`)  2. Docker Hub pull token  3. Admin CIDR  4. GitHub repo + deploy key
5. Registrar access for `lab.karansiddhu.com`. All secrets go in `.env`.
