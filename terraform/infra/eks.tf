# EKS with Pod Identity (not IRSA). Node group is x86_64 (AL2023) because the
# first-party images are amd64 single-arch (load-bearing — ARCHITECTURE.md §7).

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = local.name
  cluster_version = var.eks_version

  # Public endpoint, but LOCKED to admin CIDRs (fail-closed) — never 0.0.0.0/0.
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = local.admin_cidrs

  # Give the Terraform caller cluster-admin so kubectl works right after apply.
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Cross-node pod-to-pod on ALL ports. The module default only allows node-to-node
  # on ephemeral ports (1025-65535), so a pod service on a low port (e.g. TEI:80) is
  # unreachable when caller and callee land on different nodes. Load-bearing — without
  # it, embeddings hang with no obvious error (ARCHITECTURE.md §7).
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "node-to-node all ports (pods on low ports, e.g. TEI:80)"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
  }

  cluster_addons = {
    coredns                = {}
    kube-proxy             = {}
    eks-pod-identity-agent = {} # powers Pod Identity
    vpc-cni                = { before_compute = true }
    aws-ebs-csi-driver     = {} # gp3 PVs; its IAM is a Pod Identity assoc below
  }

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD" # x86_64 — first-party images are amd64
      instance_types = var.node_instance_types
      disk_size      = var.node_disk_size # large: many big ML/MCP images per node

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size
    }
  }
}

# gp3 is made the default StorageClass via k8s/gitops/foundation — the
# EBS-CSI addon ships a gp2 SC by default.
