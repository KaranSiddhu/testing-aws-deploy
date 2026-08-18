#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Copy every image in images.txt from its source registry into ECR.
#
#   images/mirror-to-ecr.sh
#
# Requires: docker, aws cli, and the ECR repositories to exist (terraform
# aws/30-data creates them).
#
# WHY `docker buildx imagetools create` AND NOT `docker pull` + `push`:
#
# Our images are multi-architecture - one tag pointing at an index that contains
# both an amd64 and an arm64 build. `docker pull` RESOLVES that index and
# downloads only the variant matching the machine it runs on. On your arm64 Mac
# that is the arm64 build, and pushing it to ECR would give the amd64 EKS nodes
# an image they cannot execute:
#
#     exec /usr/local/bin/uvicorn: exec format error
#
# `imagetools create` copies the INDEX, so both architectures arrive intact. It
# also never downloads the layers to your laptop - the registries transfer them
# directly - so it is much faster.
#
# AWNIC's runbook warns about the same trap and reaches for `crane` instead.
# imagetools ships with Docker, so there is nothing extra to install.
# -----------------------------------------------------------------------------
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="${HERE}/images.txt"

AWS_REGION="${AWS_REGION:-us-east-1}"

command -v docker >/dev/null || { echo "docker is required" >&2; exit 1; }
command -v aws >/dev/null || { echo "aws cli is required" >&2; exit 1; }

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo ""
echo "=================================================="
echo "  mirroring into ${REGISTRY}"
echo "=================================================="

# ECR login tokens last 12 hours. Re-running this is harmless.
echo "  logging in..."
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY" >/dev/null

while read -r source repo tag; do
  # Skip blank lines and comments.
  [[ -z "${source:-}" || "$source" == \#* ]] && continue

  src="${source}:${tag}"
  dst="${REGISTRY}/${repo}:${tag}"

  echo ""
  echo "  ${src}"
  echo "    -> ${dst}"

  # Idempotent: ECR repositories are IMMUTABLE, so re-pushing an existing tag
  # is rejected. Skip it rather than failing the whole run.
  if aws ecr describe-images --region "$AWS_REGION" \
       --repository-name "$repo" --image-ids "imageTag=${tag}" >/dev/null 2>&1; then
    echo "    already present, skipping"
    continue
  fi

  docker buildx imagetools create --tag "$dst" "$src"
  echo "    done"
done < "$MANIFEST"

echo ""
echo "=================================================="
echo "  verifying architectures"
echo "=================================================="
while read -r source repo tag; do
  [[ -z "${source:-}" || "$source" == \#* ]] && continue
  echo ""
  echo "  ${repo}:${tag}"
  # If this shows only one architecture, the mirror used `docker pull`
  # somewhere and the EKS nodes will fail with `exec format error`.
  docker buildx imagetools inspect "${REGISTRY}/${repo}:${tag}" \
    | grep -E "^\s+Platform:" | sed 's/^/    /'
done < "$MANIFEST"

echo ""
echo "  Both linux/amd64 and linux/arm64 must appear above."
echo ""
