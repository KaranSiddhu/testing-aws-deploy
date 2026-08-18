#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Destroy every billing resource, in the correct order.
#
#   terraform/destroy.sh              destroy 30 -> 20 -> 10
#   terraform/destroy.sh --yes        skip the confirmation
#
# RUN THIS AT THE END OF EVERY SESSION. The EKS control plane bills $0.10/hour
# whether or not anything is deployed. Left up around the clock the whole stack
# is ~$3.86/day; destroyed between sessions a six-hour session costs ~$0.97.
#
# ORDER IS REVERSE OF APPLY, and it matters. Destroying 10-network first fails,
# because the VPC still contains a cluster and a database. AWS refuses, the
# apply half-completes, and you are left with orphaned resources that still
# bill and that Terraform no longer tracks cleanly.
#
# 00-prereq IS DELIBERATELY LEFT ALONE. It holds the state of everything else
# and costs a fraction of a cent per month. Destroying it would mean Terraform
# forgetting what it built while the resources carried on existing and billing.
# -----------------------------------------------------------------------------
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LAYERS=(30-data 20-cluster 10-network)

if [ "${1:-}" != "--yes" ]; then
  echo ""
  echo "  This destroys, in order:"
  for l in "${LAYERS[@]}"; do echo "      $l"; done
  echo ""
  echo "  The RDS database goes with it. skip_final_snapshot is true, so"
  echo "  THERE IS NO BACKUP. Any data in it is gone."
  echo ""
  echo "  00-prereq (the state bucket) is left alone."
  echo ""
  read -r -p "  Type 'destroy' to continue: " answer
  [ "$answer" = "destroy" ] || { echo "  aborted"; exit 1; }
fi

for layer in "${LAYERS[@]}"; do
  echo ""
  echo "=================================================="
  echo "  destroying $layer"
  echo "=================================================="
  cd "${HERE}/aws/${layer}"

  # init is safe to re-run and makes the script work on a fresh clone.
  terraform init -input=false >/dev/null
  terraform destroy -auto-approve
done

echo ""
echo "=================================================="
echo "  done"
echo "=================================================="
cat <<'EOF'

  Verify nothing is still billing:

      aws eks list-clusters --region us-east-1
      aws rds describe-db-instances --region us-east-1 --query 'DBInstances[].DBInstanceIdentifier'
      aws ec2 describe-instances --region us-east-1 \
        --filters "Name=instance-state-name,Values=running" \
        --query 'Reservations[].Instances[].InstanceId'

  All three should be empty. If an EKS cluster survives a failed destroy it
  keeps billing $2.40/day in silence.

EOF
