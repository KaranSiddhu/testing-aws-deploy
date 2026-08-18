#!/usr/bin/env bash
# One-time per AWS account: create the S3 bucket that holds Terraform state, then
# write terraform/infra/backend.hcl pointing at it. Idempotent — safe to re-run.
# The bucket name is DERIVED from the account id, so there's nothing to invent.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; [ -f .env ] && . ./.env; set +a

REGION="${AWS_REGION:-us-east-1}"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="magoneai-tf-state-${ACCOUNT}"

echo "Account: $ACCOUNT   Region: $REGION   State bucket: $BUCKET"

if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "Bucket already exists — reusing."
else
  echo "Creating state bucket..."
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null
  else
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION" >/dev/null
  fi
  aws s3api put-bucket-versioning --bucket "$BUCKET" \
    --versioning-configuration Status=Enabled
  aws s3api put-bucket-encryption --bucket "$BUCKET" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
  aws s3api put-public-access-block --bucket "$BUCKET" \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
fi

cat > terraform/infra/backend.hcl <<EOF
bucket = "$BUCKET"
region = "$REGION"
EOF
echo "Wrote terraform/infra/backend.hcl  →  bucket=$BUCKET region=$REGION"
echo "Next: bin/deploy.sh infra"
