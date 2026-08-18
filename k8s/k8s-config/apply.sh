#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# dummy-hello bootstrap
#
# Usage:
#   ./apply.sh                 full bootstrap for $PLATFORM, phases in order
#   ./apply.sh 00 10           selected phases only
#
# Everything that must exist BEFORE ArgoCD can do anything, in order:
#
#   00-foundation   namespace + the db-credentials Secret
#   06-ingress      ingress-nginx            (PLATFORM=kind only)
#   10-argocd       ArgoCD, the AppProject and the root Application
#   07-routes       the app's Ingress        (flavour depends on PLATFORM)
#
# After this, ArgoCD reconciles everything else from
# k8s/argocd/envs/$PLATFORM/.
#
# WHY THIS EXISTS AT ALL: ArgoCD cannot install ArgoCD, and secrets cannot live
# in git for it to read. Something has to run first, imperatively, in order.
# Modelled on trinity-magure-deploy/k8s/k8s-config/apply.sh.
#
# IDEMPOTENT. Re-run it as often as you like. That is what makes it a recovery
# tool and not just a first-day script.
#
# Prereqs:
#   kind  ->  kind create cluster --config kind/cluster.yaml
#   eks   ->  terraform layers applied, then
#             aws eks update-kubeconfig --region us-east-1 --name dummy-hello
#             images/mirror-to-ecr.sh
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
# Not defensive padding. Under `set -u` the shell aborts on an unset variable,
# but envsubst does not: it renders an unset variable as an EMPTY STRING and
# exits 0. A typo'd POSTGRES_PASSWORD would produce a Secret with a blank
# password, apply cleanly, and fail much later as an authentication error that
# points at the database rather than at env.sh.
# ---------------------------------------------------------------------------
REQUIRED=(PLATFORM NS POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB APP_HOST API_HOST ARGOCD_HOST)

case "${PLATFORM:-}" in
  kind) ;;
  eks)
    # On EKS the certificate ARN is not optional: without it the ALB has no TLS
    # and the Ingress is rejected.
    REQUIRED+=(CERT_ARN)
    ;;
  *)
    echo "ERROR: PLATFORM must be 'kind' or 'eks' (got '${PLATFORM:-}')"
    exit 1
    ;;
esac

for var in "${REQUIRED[@]}"; do
  if [[ -z "${!var:-}" || "${!var:-}" == REPLACE_* ]]; then
    echo "ERROR: $var is unset, empty, or still a REPLACE_ placeholder in env.sh"
    exit 1
  fi
done

# Guard against the expensive mistake: bootstrapping the wrong cluster.
#
# You will have both a kind context and an EKS context in ~/.kube/config, and
# they are one arrow-key apart in your shell history.
CONTEXT="$(kubectl config current-context)"
case "$PLATFORM" in
  kind) [[ "$CONTEXT" == kind-* ]] || { echo "ERROR: PLATFORM=kind but kubectl context is '$CONTEXT'"; exit 1; } ;;
  eks) [[ "$CONTEXT" == *eks* || "$CONTEXT" == arn:aws:* ]] || { echo "ERROR: PLATFORM=eks but kubectl context is '$CONTEXT'"; exit 1; } ;;
esac

log() { echo ""; echo "=================================================="; echo "  $1"; echo "=================================================="; }

log "PLATFORM=${PLATFORM}  context=${CONTEXT}"

# ---------------------------------------------------------------------------
# Render .tpl files by substituting environment variables.
#
# Plain envsubst replaces only shell-format names ($NAME and ${NAME}). It leaves
# positional ($1) and command substitution ($(...)) intact, which matters
# because manifests legitimately contain both.
# ---------------------------------------------------------------------------
render() {
  local tpl="$1"
  local out="${tpl%.tpl}"
  envsubst < "$tpl" > "$out"
  echo "  rendered ${out#"${REPO_ROOT}/"}"
}

render_all() {
  log "Rendering templates from env.sh"

  # URL-encode the password before it goes into DATABASE_URL. A raw @ : / ? # &
  # silently truncates the URL, and the resulting error ("could not translate
  # host name") sends you looking at DNS instead of at the password.
  export POSTGRES_PASSWORD_ENCODED
  POSTGRES_PASSWORD_ENCODED=$(python3 -c \
    "import urllib.parse,os;print(urllib.parse.quote(os.environ['POSTGRES_PASSWORD'],safe=''))")

  # On kind the database is a Service called `postgres` in this namespace. On
  # eks it is RDS, and the full URL comes from `terraform output -raw
  # database_url` via DATABASE_URL_OVERRIDE.
  export DATABASE_URL
  if [ -n "${DATABASE_URL_OVERRIDE:-}" ]; then
    DATABASE_URL="$DATABASE_URL_OVERRIDE"
    echo "  DATABASE_URL: from DATABASE_URL_OVERRIDE"
  else
    DATABASE_URL="postgresql+asyncpg://${POSTGRES_USER}:${POSTGRES_PASSWORD_ENCODED}@postgres:5432/${POSTGRES_DB}"
    echo "  DATABASE_URL: built for in-cluster postgres"
  fi

  while IFS= read -r tpl; do
    render "$tpl"
  done < <(find "$SCRIPT_DIR" "${REPO_ROOT}/k8s/argocd/bootstrap" -name '*.yaml.tpl' | sort)
}

# ---------------------------------------------------------------------------
phase_00() {
  log "00-foundation: namespace and secrets"
  kubectl apply -f "${SCRIPT_DIR}/00-foundation/namespace.yaml"
  kubectl apply -f "${SCRIPT_DIR}/00-foundation/secrets.yaml"
  echo "  secret keys:"
  kubectl get secret db-credentials -n "$NS" -o go-template='{{range $k,$v := .data}}    {{$k}}{{"\n"}}{{end}}'
}

# ---------------------------------------------------------------------------
# 06-ingress: kind only.
#
# On EKS the ingress controller is the AWS Load Balancer Controller, deployed by
# ArgoCD from k8s/argocd/envs/eks/ at sync-wave 0. It needs no imperative step,
# because unlike ArgoCD it is not required in order to install ArgoCD.
# ---------------------------------------------------------------------------
phase_06() {
  if [ "$PLATFORM" != "kind" ]; then
    log "06-ingress: skipped (PLATFORM=${PLATFORM}, the ALB controller is an ArgoCD Application)"
    return
  fi

  log "06-ingress: ingress-nginx"
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
phase_10() {
  log "10-argocd: install"
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

  # --server-side --force-conflicts is required: ArgoCD's CRDs are larger than
  # the annotation client-side apply uses to remember the last state.
  kubectl apply -n argocd --server-side --force-conflicts -k "${SCRIPT_DIR}/10-argocd"

  echo "  waiting for ArgoCD to be ready..."
  kubectl wait --for=condition=available --timeout=300s \
    deployment/argocd-server \
    deployment/argocd-repo-server \
    deployment/argocd-applicationset-controller \
    -n argocd

  log "10-argocd: hand over to GitOps (envs/${PLATFORM})"
  # The AppProject first. An Application naming a project that does not exist
  # sits at InvalidSpecError forever, with no other symptom.
  kubectl apply -f "${REPO_ROOT}/k8s/argocd/bootstrap/00-project.yaml"

  # The root Application, and NOTHING else from that directory.
  #
  # Applying k8s/argocd/envs/<platform>/ directly with kubectl would create the
  # children as independent Applications, each with its own sync loop, and every
  # sync-wave annotation would become inert. The waves would read like ordering
  # and provide none.
  kubectl apply -f "${REPO_ROOT}/k8s/argocd/bootstrap/01-app-of-apps.yaml"

  # Only useful on kind, where ingress-nginx serves it. On EKS the ArgoCD UI
  # stays behind `kubectl port-forward` - exposing a cluster admin console to
  # the internet needs authentication decisions we are not making here.
  if [ "$PLATFORM" = "kind" ]; then
    kubectl apply -f "${SCRIPT_DIR}/10-argocd/argocd-server-ingress.yaml"
  fi
}

# ---------------------------------------------------------------------------
# 07-routes: the app's Ingress, in the flavour this platform needs.
#
# Runs AFTER 10, because it points at Services that ArgoCD creates. Kubernetes
# tolerates the reverse order (an Ingress with no backend just 503s until the
# Service appears) but this way a clean run has no transient errors to explain.
# ---------------------------------------------------------------------------
phase_07() {
  case "$PLATFORM" in
    kind)
      log "07-routes: ingress-nginx routes"
      kubectl apply -f "${SCRIPT_DIR}/07-routes/ingress-nginx.yaml"
      ;;
    eks)
      log "07-routes: ALB routes"
      echo "  waiting for ArgoCD to create the AWS Load Balancer Controller..."

      # TWO waits, and the first one is not redundant.
      #
      # `kubectl wait --for=condition=available` fails IMMEDIATELY with
      # "NotFound" if the object does not exist yet - it does not wait for
      # something to appear. And at this point in the bootstrap it will not
      # exist: the root Application was applied seconds ago and ArgoCD has not
      # finished creating its children.
      #
      # --for=create waits for the object to come into existence. Only then
      # does waiting for it to become available make sense.
      kubectl wait --namespace kube-system \
        --for=create --timeout=300s \
        deployment/aws-load-balancer-controller

      echo "  waiting for it to become available..."
      # Its admission webhook rejects Ingress objects until it is running, and
      # the error is a webhook connection failure that says nothing about the
      # controller still starting.
      kubectl wait --namespace kube-system \
        --for=condition=available --timeout=300s \
        deployment/aws-load-balancer-controller
      kubectl apply -f "${SCRIPT_DIR}/07-routes/ingress-alb.yaml"
      echo ""
      echo "  The ALB takes 2-3 minutes to provision. Watch for its address:"
      echo "      kubectl get ingress -n ${NS} -w"
      ;;
  esac
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

EOF

  if [ "$PLATFORM" = "kind" ]; then
    cat <<EOF
      app     http://${APP_HOST}:8080
      argocd  http://${ARGOCD_HOST}:8080

EOF
  else
    cat <<EOF
  Once the ALB has an address, point DNS at it:

      kubectl get ingress -n ${NS} -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'

  Add BOTH as CNAMEs at Hostinger:

      ${APP_HOST}  ->  <that hostname>
      ${API_HOST}  ->  <that hostname>

  Then:

      app     https://${APP_HOST}
      api     https://${API_HOST}/docs
      argocd  kubectl port-forward svc/argocd-server -n argocd 8081:443

EOF
  fi

  cat <<'EOF'
  ArgoCD admin password:

      kubectl -n argocd get secret argocd-initial-admin-secret \
        -o jsonpath='{.data.password}' | base64 -d; echo

EOF
}

main "$@"
