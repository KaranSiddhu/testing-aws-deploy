#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# dummy-hello bootstrap
#
# Usage:
#   ./apply.sh                 full bootstrap, phases in order
#   ./apply.sh 00 10           selected phases only
#
# Everything that must exist BEFORE ArgoCD can do anything, in order:
#
#   00-foundation   namespace + the db-credentials Secret
#   06-ingress      the ingress controller
#   10-argocd       ArgoCD itself, then the AppProject and root Application
#   07-routes       the Ingress for the app (after ArgoCD created the Services)
#
# After this, ArgoCD reconciles everything else from k8s/argocd/applications/.
#
# WHY THIS EXISTS AT ALL: ArgoCD cannot install ArgoCD, and secrets cannot live
# in git for it to read. Something has to run first, imperatively, in order.
# Modelled on trinity-magure-deploy/k8s/k8s-config/apply.sh.
#
# IDEMPOTENT. Re-run it as often as you like. That is what makes it a recovery
# tool and not just a first-day script.
#
# Prereqs: a cluster and a kubectl context pointing at it. For kind:
#   kind create cluster --config kind/cluster.yaml
# -----------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/env.sh"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: env.sh not found."
  echo "       cp env.sh.example env.sh   then fill it in."
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

# ---------------------------------------------------------------------------
# Validate every variable BEFORE rendering anything.
#
# This is not defensive padding. Under `set -u` a shell would abort on an unset
# variable, but envsubst does not: it renders an unset variable as an EMPTY
# STRING and exits 0. So a typo'd POSTGRES_PASSWORD produces a Secret with a
# blank password, applies cleanly, and fails much later as an authentication
# error that points at the database rather than at env.sh.
# ---------------------------------------------------------------------------
for var in NS POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB \
  APP_HOST ARGOCD_HOST; do
  if [[ -z "${!var:-}" || "${!var:-}" == REPLACE_* ]]; then
    echo "ERROR: $var is unset, empty, or still a REPLACE_ placeholder in env.sh"
    exit 1
  fi
done

log() { echo ""; echo "=================================================="; echo "  $1"; echo "=================================================="; }

# ---------------------------------------------------------------------------
# Render one .tpl by substituting environment variables.
#
# Plain envsubst replaces only shell-format names ($NAME and ${NAME}). It leaves
# positional ($1) and command substitution ($(...)) intact, which matters
# because manifests legitimately contain both.
# ---------------------------------------------------------------------------
render() {
  local tpl="$1"
  local out="${tpl%.tpl}"
  envsubst < "$tpl" > "$out"
  echo "  rendered $(basename "$out")"
}

render_all() {
  log "Rendering templates from env.sh"

  # URL-encode the password before it goes into DATABASE_URL. A raw @ : / ? # &
  # silently truncates the URL, and the resulting error ("could not translate
  # host name") sends you looking at DNS instead of at the password.
  export POSTGRES_PASSWORD_ENCODED
  POSTGRES_PASSWORD_ENCODED=$(python3 -c \
    "import urllib.parse,os;print(urllib.parse.quote(os.environ['POSTGRES_PASSWORD'],safe=''))")

  while IFS= read -r tpl; do
    render "$tpl"
  done < <(find "$SCRIPT_DIR" -name '*.yaml.tpl' | sort)
}

# ---------------------------------------------------------------------------
# 00-foundation: namespace and the database Secret.
# ---------------------------------------------------------------------------
phase_00() {
  log "00-foundation: namespace and secrets"
  kubectl apply -f "${SCRIPT_DIR}/00-foundation/namespace.yaml"
  kubectl apply -f "${SCRIPT_DIR}/00-foundation/secrets.yaml"
  echo "  secret keys:"
  kubectl get secret db-credentials -n "$NS" -o jsonpath='{range .data}{"\n"}{end}' >/dev/null 2>&1 || true
  kubectl get secret db-credentials -n "$NS" -o go-template='{{range $k,$v := .data}}    {{$k}}{{"\n"}}{{end}}'
}

# ---------------------------------------------------------------------------
# 06-ingress: the ingress controller.
#
# The kind-provider manifest, because the generic one waits forever for a cloud
# load balancer to give it an external IP. The kind variant uses hostPort on the
# node labelled ingress-ready=true, which kind/cluster.yaml sets.
# ---------------------------------------------------------------------------
phase_06() {
  log "06-ingress: ingress-nginx"
  # Kustomization rather than a bare URL, because the upstream manifest needs a
  # nodeSelector patch to land on the node whose ports kind actually maps.
  # See 06-ingress/kustomization.yaml.
  kubectl apply -k "${SCRIPT_DIR}/06-ingress"

  echo "  waiting for the controller to be ready..."
  # The admission webhook rejects Ingress objects until it is up, so creating a
  # route before this finishes fails with a confusing connection-refused error.
  kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=180s
}

# ---------------------------------------------------------------------------
# 10-argocd: ArgoCD, then the bootstrap that hands everything else over to it.
# ---------------------------------------------------------------------------
phase_10() {
  log "10-argocd: install"
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

  # --server-side --force-conflicts is required: ArgoCD's CRDs are larger than
  # the annotation that client-side apply uses to remember the last state.
  kubectl apply -n argocd --server-side --force-conflicts -k "${SCRIPT_DIR}/10-argocd"

  echo "  waiting for ArgoCD to be ready..."
  kubectl wait --for=condition=available --timeout=300s \
    deployment/argocd-server \
    deployment/argocd-repo-server \
    deployment/argocd-applicationset-controller \
    -n argocd

  log "10-argocd: hand over to GitOps"
  # The AppProject first. An Application naming a project that does not exist
  # sits at InvalidSpecError forever, with no other symptom.
  kubectl apply -f "${REPO_ROOT}/k8s/argocd/bootstrap/00-project.yaml"

  # The root Application, and NOTHING else from that directory.
  #
  # Applying k8s/argocd/applications/ directly with kubectl would create the
  # children as independent Applications, each with its own sync loop, and every
  # sync-wave annotation on them would become inert. The waves would read like
  # ordering and provide none.
  kubectl apply -f "${REPO_ROOT}/k8s/argocd/bootstrap/01-app-of-apps.yaml"

  kubectl apply -f "${SCRIPT_DIR}/10-argocd/argocd-server-ingress.yaml"
}

# ---------------------------------------------------------------------------
# 07-routes: the app's Ingress.
#
# Runs AFTER 10, because it points at the fe Service, which ArgoCD creates.
# Kubernetes tolerates the reverse order (an Ingress with no backend just 503s
# until the Service appears) but the ordering here means a clean run has no
# transient errors to explain away.
# ---------------------------------------------------------------------------
phase_07() {
  log "07-routes: application ingress"
  kubectl apply -f "${SCRIPT_DIR}/07-routes/ingress.yaml"
}

# ---------------------------------------------------------------------------
main() {
  local phases=("$@")
  if [ ${#phases[@]} -eq 0 ]; then
    phases=(00 06 10 07)
  fi

  render_all

  for phase in "${phases[@]}"; do
    case "$phase" in
      00) phase_00 ;;
      06) phase_06 ;;
      07) phase_07 ;;
      10) phase_10 ;;
      *) echo "unknown phase: $phase (valid: 00 06 07 10)"; exit 1 ;;
    esac
  done

  log "Bootstrap complete"
  cat <<EOF

  ArgoCD is now reconciling the workloads. Watch it:

      kubectl get applications -n argocd -w

  Then:

      app     http://${APP_HOST}:8080
      argocd  http://${ARGOCD_HOST}:8080

  ArgoCD admin password:

      kubectl -n argocd get secret argocd-initial-admin-secret \\
        -o jsonpath='{.data.password}' | base64 -d; echo

EOF
}

main "$@"
