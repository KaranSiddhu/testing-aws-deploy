# EKS cluster and node group.
#
# THE EXPENSIVE LAYER: $0.10/hour for the control plane plus the nodes,
# regardless of whether anything is deployed. ~$3.40/day. Destroy it at the end
# of every session.
#
# Also the SLOW layer: expect ~12 minutes to apply and ~10 to destroy. AWS
# genuinely takes that long. It is not hung.

module "eks" {
  source = "../../modules/aws/eks"

  name               = var.project
  kubernetes_version = var.kubernetes_version
  subnet_ids         = data.terraform_remote_state.network.outputs.public_subnet_ids
}

module "node_group" {
  source = "../../modules/aws/node-group"

  name          = var.project
  cluster_name  = module.eks.cluster_name
  subnet_ids    = data.terraform_remote_state.network.outputs.public_subnet_ids
  instance_type = var.node_instance_type
  node_count    = var.node_count
}

# ---------------------------------------------------------------------------
# EKS managed add-ons.
#
# These three make a cluster actually work:
#   vpc-cni     gives every pod a real VPC IP address
#   coredns     in-cluster DNS, so "be" resolves to the be Service
#   kube-proxy  implements Services on each node
#
# EKS installs them automatically as "self-managed" if you say nothing, but then
# nothing upgrades them and nothing records which version you have. Declaring
# them as managed add-ons makes the versions explicit and upgradeable.
#
# ORDER MATTERS: coredns is a Deployment and needs a node to run on, so it must
# come after the node group. Without depends_on it is created first, sits
# Degraded, and the apply fails on a timeout that says nothing about ordering.
# ---------------------------------------------------------------------------
resource "aws_eks_addon" "this" {
  for_each = toset(["vpc-cni", "coredns", "kube-proxy"])

  cluster_name = module.eks.cluster_name
  addon_name   = each.value

  # Take the default version for this Kubernetes version. Pinning exact add-on
  # versions is the production choice; it also means finding the compatible
  # version by hand every upgrade.
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [module.node_group]
}
