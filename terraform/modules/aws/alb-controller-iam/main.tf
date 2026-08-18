# IAM policy and IRSA role for the AWS Load Balancer Controller.
#
# The controller runs as a pod and creates real AWS load balancers on your
# behalf, so it needs genuine AWS permissions. IRSA is how it gets them without
# a static key existing anywhere.
#
# THE POLICY IS VENDORED, not written by hand. iam_policy.json is a byte-for-byte
# copy of the controller's own published policy for v3.5.0:
#
#   https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/
#     v3.5.0/docs/install/iam_policy.json
#
# 16 statements across acm, cognito-idp, ec2, elasticloadbalancing, iam, shield,
# waf-regional and wafv2. Hand-trimming it is a classic way to lose an afternoon:
# the controller fails on ONE missing action, deep inside a reconcile, and the
# error surfaces as an Ingress that never gets an address with the real reason
# buried in the controller's logs.
#
# AWNIC vendors the same file, pinned to the same v3.5.0.
#
# UPGRADING: bump the URL, re-download, diff it. The policy changes between
# controller versions, and a controller newer than its policy fails exactly the
# same silent way.

resource "aws_iam_policy" "this" {
  name        = "${var.name}-alb-controller"
  description = "AWS Load Balancer Controller v3.5.0, vendored upstream policy"
  policy      = file("${path.module}/iam_policy.json")
  tags        = { Name = "${var.name}-alb-controller" }
}

module "irsa" {
  source = "../irsa"

  name              = "${var.name}-alb-controller"
  oidc_provider_arn = var.oidc_provider_arn
  oidc_provider_url = var.oidc_provider_url

  # Must match the ServiceAccount the controller's Helm chart creates. The
  # chart's default name is aws-load-balancer-controller in kube-system; the
  # ArgoCD Application must not override either, or the trust policy stops
  # matching and every AWS call is denied with AccessDenied.
  namespace       = var.namespace
  service_account = var.service_account

  # Static key, computed value. The key is just a label for the resource
  # address; it exists so Terraform can plan without knowing the ARN yet.
  policy_arns = {
    alb-controller = aws_iam_policy.this.arn
  }
}
