# EKS Pod Identity: map k8s ServiceAccounts → IAM roles (no static keys, no IRSA).
# Roles: app (S3 + Secrets Manager + KMS), vault (KMS unseal), ebs-csi.
# (external-dns + ESO roles live in dns.tf / secrets-bridge.tf.)

# Trust policy shared by all Pod Identity roles.
data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole", "sts:TagSession"]
  }
}

# ---------------------------------------------------------------------------
# 1. App role  →  ServiceAccount magoneai-app
# ---------------------------------------------------------------------------
resource "aws_iam_role" "app" {
  name               = "${local.name}-app"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

data "aws_iam_policy_document" "app" {
  # S3 docs bucket read/write (the app's object storage).
  statement {
    sid       = "S3Bucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.docs.arn]
  }
  statement {
    sid       = "S3Objects"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.docs.arn}/*"]
  }

  # Read infra secrets; PutSecretValue lets the Vault-init hook write the freshly
  # generated root token back to app-secrets → ESO syncs it into the k8s Secret.
  statement {
    sid       = "SecretsManagerReadWrite"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret", "secretsmanager:PutSecretValue"]
    resources = ["arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${local.name}-*"]
  }

  # NOTE: the app intentionally gets NO KMS access. App-side field encryption uses a
  # Fernet key (api-key-encryption-key), not KMS; the KMS key is Vault's unseal key
  # only. Granting the app decrypt on it would let a compromised app pod decrypt
  # Vault's seal-wrapped storage offline.
}

resource "aws_iam_role_policy" "app" {
  name   = "app"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app.json
}

resource "aws_eks_pod_identity_association" "app" {
  cluster_name    = module.eks.cluster_name
  namespace       = var.k8s_namespace
  service_account = var.app_service_account
  role_arn        = aws_iam_role.app.arn
}

# ---------------------------------------------------------------------------
# 2. Vault role  →  ServiceAccount vault  (auto-unseal via awskms)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "vault" {
  name               = "${local.name}-vault"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

data "aws_iam_policy_document" "vault" {
  statement {
    sid       = "VaultUnseal"
    effect    = "Allow"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:DescribeKey"]
    resources = [aws_kms_key.vault.arn]
  }
}

resource "aws_iam_role_policy" "vault" {
  name   = "vault"
  role   = aws_iam_role.vault.id
  policy = data.aws_iam_policy_document.vault.json
}

resource "aws_eks_pod_identity_association" "vault" {
  cluster_name    = module.eks.cluster_name
  namespace       = var.k8s_namespace
  service_account = var.vault_service_account
  role_arn        = aws_iam_role.vault.arn
}

# ---------------------------------------------------------------------------
# 3. EBS CSI role  →  ServiceAccount kube-system/ebs-csi-controller-sa
# ---------------------------------------------------------------------------
resource "aws_iam_role" "ebs_csi" {
  name               = "${local.name}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi.arn
}
