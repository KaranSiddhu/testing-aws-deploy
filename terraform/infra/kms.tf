# KMS key for Vault auto-unseal (seal "awskms") only. The Vault pod assumes the vault
# Pod Identity role (iam-pod-identity.tf), which is granted use of this key. The app
# does NOT use KMS (field encryption is app-side Fernet), so it gets no access here.

resource "aws_kms_key" "vault" {
  description             = "${local.name} Vault auto-unseal"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "vault" {
  name          = "alias/${local.name}-vault"
  target_key_id = aws_kms_key.vault.key_id
}
