#!/usr/bin/env bash
# Resilient teardown (order learned the hard way):
#   1. stop ArgoCD + external-dns so they don't recreate the LB / DNS records
#   2. delete the ingress-nginx Service → its ELB deprovisions (else VPC destroy fails)
#   3. terraform destroy (force_destroy on the Route53 zone clears external-dns records)
#   4. sweep orphaned StatefulSet EBS volumes (dynamically provisioned, not in TF state)
set -uo pipefail
cd "$(dirname "$0")/.."
set -a; [ -f .env ] && . ./.env; set +a
REGION="${AWS_REGION:-us-east-1}"
CLUSTER="magoneai"

echo "== teardown $CLUSTER =="
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" >/dev/null 2>&1 || echo "(cluster unreachable — continuing)"

# 1+2. quiesce reconcilers, drop the ingress ELB
kubectl -n argocd scale statefulset argocd-application-controller --replicas=0 2>/dev/null || true
kubectl -n external-dns scale deploy external-dns --replicas=0 2>/dev/null || true
kubectl delete svc ingress-nginx-controller -n ingress-nginx --ignore-not-found 2>/dev/null || true

cd terraform/infra
terraform init -reconfigure -backend-config=backend.hcl >/dev/null
VPC="$(terraform output -raw vpc_id 2>/dev/null || true)"
if [ -n "$VPC" ]; then
  echo "waiting for ELBs in $VPC to deprovision..."
  for _ in $(seq 1 18); do
    c=$(aws elb describe-load-balancers --region "$REGION" --query "length(LoadBalancerDescriptions[?VPCId=='$VPC'])" --output text 2>/dev/null || echo 0)
    v=$(aws elbv2 describe-load-balancers --region "$REGION" --query "length(LoadBalancers[?VpcId=='$VPC'])" --output text 2>/dev/null || echo 0)
    [ "$c" = 0 ] && [ "$v" = 0 ] && break
    sleep 10
  done
fi

# 3. destroy infra
terraform destroy -auto-approve -var-file=terraform.tfvars

# 4. sweep orphaned EBS volumes for this cluster
for vol in $(aws ec2 describe-volumes --region "$REGION" \
    --filters Name=status,Values=available "Name=tag:kubernetes.io/cluster/$CLUSTER,Values=owned" \
    --query 'Volumes[].VolumeId' --output text 2>/dev/null); do
  aws ec2 delete-volume --region "$REGION" --volume-id "$vol" 2>/dev/null && echo "swept $vol"
done

echo "Teardown complete. (Remove the registrar NS delegation manually if desired.)"
