#!/usr/bin/env bash
# Point ArgoCD at your fork in one shot.
#
# ArgoCD reconciles from git, so the repo it pulls is baked into the app manifests (the
# `repoURL` fields), NOT a .env value. This rewrites every `<org>/magoneai-aws` reference
# under k8s/ so they all point at your fork. Everything stays concrete/committed — no
# templating, no generator.
#
# After running: review `git diff` → commit + push → add a read-only deploy key to your
# fork (RUNBOOK 0.4) so ArgoCD can read it.
set -euo pipefail
cd "$(dirname "$0")/.."

NEW="${1:?usage: set-repo.sh <org/repo>   e.g. set-repo.sh acme/magoneai-aws}"
# Derive the current value from the committed repoURL so this keeps working after a rename.
OLD="$(grep -m1 'repoURL' k8s/apps/app-of-apps.yaml | sed -E 's#.*github\.com[:/]([^[:space:]]+)\.git.*#\1#')"
[ -n "$OLD" ] && [ "$OLD" != "$(grep -m1 'repoURL' k8s/apps/app-of-apps.yaml)" ] \
  || { echo "could not read current repo from k8s/apps/app-of-apps.yaml repoURL"; exit 1; }
if [ "$OLD" = "$NEW" ]; then echo "repo already '$NEW' — nothing to do"; exit 0; fi

echo "Changing repo: $OLD -> $NEW"
# Literal global replace of the old org/repo string across the manifests. Review the
# `git diff` afterwards. (Manifest paths have no spaces, so word-splitting is fine here.)
n=0
for f in $(grep -rl "$OLD" k8s); do
  OLD="$OLD" NEW="$NEW" perl -i -pe 's/\Q$ENV{OLD}\E/$ENV{NEW}/g' "$f"
  n=$((n + 1))
done

echo "Rewrote $OLD -> $NEW in $n files. Review with: git diff"
echo "Then: commit + push -> add a read-only deploy key to your fork (RUNBOOK 0.4)."
