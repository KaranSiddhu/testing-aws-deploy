#!/usr/bin/env bash
# One-time ArgoCD bootstrap — the only imperative seam. After this, ArgoCD reconciles
# the entire stack from git with no further manual steps. Run after infra is up and
# kubeconfig is set. Reads the read-only deploy key from .secrets/argocd_deploy_key.
set -euo pipefail
cd "$(dirname "$0")/../.."
set -a; [ -f .env ] && . ./.env; set +a

KEY=".secrets/argocd_deploy_key"
AOA="k8s/apps/app-of-apps.yaml"
REPO_SSH="$(awk '/repoURL:/{print $2; exit}' "$AOA")"
[ -n "$REPO_SSH" ] || { echo "could not read repoURL from $AOA"; exit 1; }
[ -f "$KEY" ]      || { echo "missing $KEY (read-only GitHub deploy key)"; exit 1; }

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update >/dev/null
# Do NOT use --wait here (it hangs against EKS). Install, then wait on components.
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace --set crds.install=true
kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=180s
kubectl rollout status deploy/argocd-repo-server -n argocd --timeout=180s

# Repo credential (read-only SSH deploy key) so ArgoCD can read the private repo.
kubectl create secret generic magoneai-repo -n argocd \
  --from-literal=type=git --from-literal=url="$REPO_SSH" \
  --from-file=sshPrivateKey="$KEY" --dry-run=client -o yaml \
  | kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml \
  | kubectl apply -f -

kubectl wait --for condition=established crd/applications.argoproj.io --timeout=120s
kubectl apply -f "$AOA"
echo "Bootstrap done. Watch: kubectl get applications -n argocd -w"
