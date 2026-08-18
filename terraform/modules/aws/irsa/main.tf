# IRSA: IAM Roles for Service Accounts.
#
# THE PROBLEM IT SOLVES. A pod needs to call an AWS API - create a load
# balancer, read an S3 object. The obvious way is an access key in a Kubernetes
# Secret. That key is long-lived, it is base64 in etcd, anyone who can read
# Secrets in that namespace has it, rotating it means a redeploy, and if it
# leaks it works from anywhere on the internet until someone notices.
#
# IRSA removes the key entirely.
#
#   1. The cluster issues a short-lived, signed JWT to a pod's ServiceAccount.
#   2. AWS IAM trusts that cluster's OIDC issuer (created in 20-cluster).
#   3. The pod trades its token for temporary AWS credentials via STS.
#
# Nothing long-lived exists. Nothing to rotate, nothing to leak, and the trust
# policy below pins EXACTLY which namespace and ServiceAccount may assume the
# role - so a compromised pod elsewhere in the cluster cannot use it.
#
# This is Phase 1 section 8.3 in AWNIC's specification, and the reason its
# CLAUDE.md warns that IRSA needs the REGIONAL STS endpoint: the AWS SDK's
# global default does not route through a VPC endpoint, so a pod starts cleanly
# and fails on its first AWS call minutes later.

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    # The audience must be sts.amazonaws.com. Without this condition the role
    # would trust ANY token from this cluster, including ones minted for other
    # purposes entirely.
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # The subject pins the exact namespace and ServiceAccount. This is the line
    # that makes IRSA a security control rather than a convenience: only
    # system:serviceaccount:<ns>:<sa> may assume this role, and nothing else in
    # the cluster can.
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account}"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = var.name
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = { Name = var.name }
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = toset(var.policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = each.value
}
