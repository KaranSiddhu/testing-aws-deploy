# IAM roles that pods assume, via IRSA.
#
# FREE. IAM roles and policies cost nothing. This layer is only destroyed
# because its roles reference the cluster's OIDC provider, and leaving them
# behind after the cluster is gone would leave roles trusting an issuer that no
# longer exists.
#
# Applied AFTER 20-cluster and destroyed BEFORE it.

module "alb_controller_iam" {
  source = "../../modules/aws/alb-controller-iam"

  name              = var.project
  oidc_provider_arn = data.terraform_remote_state.cluster.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.cluster.outputs.oidc_provider_url

  # Must match what the controller's Helm chart actually creates. Change either
  # value here or in the chart and the trust policy stops matching: the pod
  # starts fine and every AWS call fails with AccessDenied, minutes later.
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
}

# NOTE: the application itself needs no IRSA role.
#
# dummy-hello-app calls no AWS APIs - it talks to Postgres and nothing else.
# Adding a role "just in case" would be handing out permissions nobody needs.
#
# When it does need one (reading from S3, say), it is four lines here plus one
# annotation on the ServiceAccount. That is the shape MagOneAI uses for object
# storage in AWNIC, and why its MINIO credentials are deliberately EMPTY: empty
# values make boto3 fall through to its default chain, which finds the IRSA
# token. Real keys there would replace pod identity with a static credential.
