# DNS: a Route53 hosted zone for the deployment domain. external-dns manages the
# A records (app + grafana) via Pod Identity. cert-manager uses HTTP-01 (not DNS-01),
# so it needs NO Route53 access. Apply outputs the NS records — delegate them once at
# the registrar (the one human step), BEFORE deploying apps so the cert issues first try.

resource "aws_route53_zone" "main" {
  name          = var.dns_zone
  force_destroy = true # destroy removes external-dns-created records too
}

# external-dns role: create/update records in this zone. Pod Identity (no static keys).
resource "aws_iam_role" "external_dns" {
  name               = "${local.name}-external-dns"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

data "aws_iam_policy_document" "external_dns" {
  statement {
    sid       = "ChangeRecords"
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = [aws_route53_zone.main.arn]
  }
  statement {
    sid       = "ListZones"
    effect    = "Allow"
    actions   = ["route53:ListHostedZones", "route53:ListResourceRecordSets", "route53:GetChange"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "external_dns" {
  name   = "external-dns"
  role   = aws_iam_role.external_dns.id
  policy = data.aws_iam_policy_document.external_dns.json
}

resource "aws_eks_pod_identity_association" "external_dns" {
  cluster_name    = module.eks.cluster_name
  namespace       = "external-dns"
  service_account = "external-dns"
  role_arn        = aws_iam_role.external_dns.arn
}
