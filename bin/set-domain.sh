#!/usr/bin/env bash
# Change the deployment's domain in one shot.
#
# The domain is committed config, NOT a .env value — ArgoCD reconciles from git and
# can't read your laptop's .env, so the app hostnames must live in the manifests. This
# rewrites every concrete spot so they stay in sync: the Terraform zone, the ArgoCD app
# hostnames (app.<domain> + grafana.<domain>), the external-dns filter, the creds URL,
# and the runbook. Everything stays concrete/committed — no templating, no generator.
#
# After running: review `git diff` → commit + push → `bin/deploy.sh infra` (creates the
# new Route53 zone) → delegate the new zone's nameservers → cert re-issues for the new host.
set -euo pipefail
cd "$(dirname "$0")/.."

NEW="${1:?usage: set-domain.sh <zone>   e.g. set-domain.sh example.com}"
OLD="$(awk -F'"' '/^dns_zone/{print $2}' terraform/infra/terraform.tfvars)"
[ -n "$OLD" ] || { echo "could not read current dns_zone from terraform/infra/terraform.tfvars"; exit 1; }
if [ "$OLD" = "$NEW" ]; then echo "domain already '$NEW' — nothing to do"; exit 0; fi

echo "Changing domain: $OLD -> $NEW"
# NOTE: a literal global replace of the old domain string across these files. Safe for
# the current content (the domain appears only as host/zone values), but review the
# `git diff` afterwards — if the old domain ever appears coincidentally elsewhere, it
# would be rewritten too.
files=(terraform/infra/terraform.tfvars bin/creds.sh RUNBOOK.md)
for f in k8s/apps/applications/*.yaml; do files+=("$f"); done

for f in "${files[@]}"; do
  perl -i -pe "s/\Q$OLD\E/$NEW/g" "$f"
done

echo "Rewrote $OLD -> $NEW in ${#files[@]} files. Review with: git diff"
echo "Then: commit + push -> bin/deploy.sh infra (new Route53 zone) -> delegate its nameservers."
