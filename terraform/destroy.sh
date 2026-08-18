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
# TWO LAYERS ARE DELIBERATELY LEFT ALONE:
#
#   00-prereq  the state bucket. Holds the state of everything else and costs a
#              fraction of a cent per month. Destroying it would mean Terraform
#              forgetting what it built while the resources carried on existing
#              and billing.
#
#   50-edge    the ACM certificate. Free, and validating it means adding CNAME
#              records by hand at Hostinger. Destroying it would mean redoing
#              that DNS work and waiting for revalidation every single session.
# -----------------------------------------------------------------------------
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

# Reverse of apply order. 40-access first: its IAM roles trust the cluster's
# OIDC provider, so they must go before the cluster does.
LAYERS=(40-access 30-data 20-cluster 10-network)

if [ "${1:-}" != "--yes" ]; then
  echo ""
  echo "  This destroys, in order:"
  for l in "${LAYERS[@]}"; do echo "      $l"; done
  echo ""
  echo "  The RDS database goes with it. skip_final_snapshot is true, so"
  echo "  THERE IS NO BACKUP. Any data in it is gone."
  echo ""
  echo "  Left alone: 00-prereq (state bucket), 50-edge (ACM certificate)."
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
      aws elbv2 describe-load-balancers --region us-east-1 \
        --query 'LoadBalancers[].LoadBalancerName'

  All four should be empty. If an EKS cluster survives a failed destroy it keeps
  billing $2.40/day in silence.

  THE LOAD BALANCER IS THE ONE TO WATCH. It is created by the AWS Load Balancer
  Controller in response to an Ingress, NOT by Terraform - so Terraform does not
  know it exists and will not remove it. Deleting the Ingress (or the whole
  cluster) normally cleans it up, but if the controller dies first the ALB is
  orphaned and bills $0.55/day forever.

  If one is left behind:
      aws elbv2 delete-load-balancer --region us-east-1 --load-balancer-arn <arn>

EOF
