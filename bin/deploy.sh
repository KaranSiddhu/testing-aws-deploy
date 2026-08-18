#!/usr/bin/env bash
# Thin deploy wrapper — sources .env so you never `export` secrets by hand.
#   bin/deploy.sh infra   provision AWS (terraform), then print the zone nameservers
#   bin/deploy.sh apps    bootstrap ArgoCD + reconcile the whole stack from git
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; [ -f .env ] && . ./.env; set +a

case "${1:-}" in
  infra)
    [ -f terraform/infra/backend.hcl ] || { echo "Run bin/init-account.sh first (it writes backend.hcl)."; exit 1; }
    cd terraform/infra
    terraform init -reconfigure -backend-config=backend.hcl
    terraform apply -var-file=terraform.tfvars
    echo
    echo "=== Delegate these nameservers at your registrar, then verify with dig before 'apps': ==="
    terraform output -json dns_zone_name_servers | tr -d '[]"' | tr ',' '\n' | sed 's/^/  /'
    echo "Next: delegate DNS → verify (dig +short NS <zone> @8.8.8.8) → bin/deploy.sh apps"
    ;;
  apps)
    bash k8s/gitops/bootstrap.sh
    echo "Watch it converge: kubectl get applications -n argocd -w"
    ;;
  *)
    echo "usage: bin/deploy.sh {infra|apps}"; exit 1 ;;
esac
