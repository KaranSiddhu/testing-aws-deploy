# EKS control plane.
#
# This is the $0.10/hour resource. It bills whether or not any node or pod
# exists, which is why `terraform destroy` at the end of a session is the single
# most valuable habit in this repo.
#
# Kubernetes version: use one on STANDARD support. A version that has fallen to
# extended support costs $0.60/hour - six times as much, for doing nothing.

# ---------------------------------------------------------------------------
# IAM role the control plane assumes.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "assume_cluster" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.name}-eks-cluster"
  assume_role_policy = data.aws_iam_policy_document.assume_cluster.json
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ---------------------------------------------------------------------------
# The cluster.
# ---------------------------------------------------------------------------
resource "aws_eks_cluster" "this" {
  name     = var.name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids = var.subnet_ids

    # Public endpoint so kubectl works from your laptop. In production you would
    # restrict this with public_access_cidrs, or turn it off entirely and reach
    # the API through a bastion - which is what AWNIC does, and why its
    # acceptance tests have to run on the bastion rather than a workstation.
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  # Who can talk to this cluster, and how.
  #
  # "API" means access is granted ONLY by EKS access entries (below). The old
  # mechanism was the aws-auth ConfigMap, edited in-cluster - which meant your
  # cluster permissions lived in a YAML file that Terraform did not manage, and
  # a bad edit could lock everyone out with no way back in.
  access_config {
    authentication_mode = "API"

    # Give the identity that runs `terraform apply` cluster-admin. Without this
    # you create a cluster you cannot connect to, and fixing it means using the
    # same identity to add an access entry anyway.
    bootstrap_cluster_creator_admin_permissions = true
  }

  # Control plane logs to CloudWatch. Off by default and easy to skip, but the
  # authenticator log is the only place that tells you WHY a kubectl call was
  # denied. Costs pennies at this scale.
  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  # IAM permissions must exist before the cluster is created, and must outlive
  # it during destroy. Terraform infers most ordering from references; this one
  # it cannot see.
  depends_on = [aws_iam_role_policy_attachment.cluster]

  tags = { Name = var.name }
}

# ---------------------------------------------------------------------------
# OIDC provider. This is what makes IRSA possible in Phase 7.
#
# It lets AWS IAM trust the tokens the cluster issues to service accounts, so a
# pod can assume an IAM role with NO static credentials anywhere - no access key
# in a Secret, nothing to leak, nothing to rotate.
#
# Created here rather than in Phase 7 because it is a property of the cluster,
# and creating it later would mean modifying the cluster layer from the app
# layer.
# ---------------------------------------------------------------------------
data "tls_certificate" "oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]

  tags = { Name = "${var.name}-oidc" }
}
