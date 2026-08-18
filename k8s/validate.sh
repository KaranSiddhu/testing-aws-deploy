#!/usr/bin/env bash
# Render every chart the way ArgoCD will, then check what comes out.
#
#   k8s/validate.sh              every chart
#   k8s/validate.sh be fe        named charts only
#
# Thin wrapper around validate.py, which is where the checks live. Needs helm
# and no cluster, so it is safe to run anywhere and fast enough for a
# pre-commit hook.
#
# PyYAML: AWNIC's version of this script simply requires it to be installed.
# We do not, because nothing in this practice repo should need a system-wide
# install. In order of preference:
#
#   1. system python3, if it already has PyYAML
#   2. `uv run --with pyyaml`, which builds a THROWAWAY environment for this
#      one command and leaves your machine untouched
#   3. tell you what to do
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

command -v helm >/dev/null 2>&1 || { echo "helm is required" >&2; exit 1; }

if python3 -c 'import yaml' 2>/dev/null; then
  exec python3 "${HERE}/validate.py" "$@"
elif command -v uv >/dev/null 2>&1; then
  exec uv run --quiet --with pyyaml python3 "${HERE}/validate.py" "$@"
else
  echo "PyYAML is not available and uv is not installed." >&2
  echo "Either install uv, or run: pip3 install --user pyyaml" >&2
  exit 1
fi
