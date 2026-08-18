# The TLS certificate for hello.karansiddhu.com and api-hello.karansiddhu.com.
#
# ==========================================================================
# THIS LAYER IS NEVER DESTROYED. destroy.sh deliberately skips it.
# ==========================================================================
#
# ACM public certificates are FREE, and validating one requires adding CNAME
# records by hand at Hostinger. If the certificate were destroyed with
# everything else you would redo that DNS work at the start of every session,
# and wait for revalidation each time.
#
# So it lives in its own layer with no dependency on the VPC or the cluster:
# apply once, validate once, reuse forever. Same reasoning as 00-prereq.
#
# ACM also renews it automatically, indefinitely, as long as the validation
# records stay in DNS. Leave them there.
#
# WHY ACM AND NOT cert-manager: on AWS the ALB terminates TLS using an ACM
# certificate directly - no controller, no ACME challenge, no renewal job, no
# rate limits. trinity uses cert-manager with Let's Encrypt only because OCI has
# no ACM equivalent. AWNIC uses ACM too, but IMPORTS a client-supplied
# certificate rather than issuing one, because its names are internal-only:
# ACM cannot issue for a name it cannot reach, and cert-manager's HTTP-01 needs
# public reachability an internal ALB does not have. Ours are public, so ACM can
# simply issue.

resource "aws_acm_certificate" "this" {
  domain_name = var.app_host

  # The API host as a Subject Alternative Name. ONE certificate covering both,
  # which is also why both names are one level under the root: a wildcard
  # matches exactly one label, so *.karansiddhu.com would cover
  # api-hello.karansiddhu.com but NOT api.hello.karansiddhu.com.
  subject_alternative_names = [var.api_host]

  # DNS validation, not EMAIL. Email validation expires and needs a human to
  # click a link every renewal. DNS validation renews silently forever as long
  # as the CNAME records remain.
  validation_method = "DNS"

  lifecycle {
    # Certificates are immutable: changing a name means a new certificate. This
    # creates the replacement BEFORE destroying the old one, so there is never a
    # moment where the ALB references a certificate that no longer exists.
    create_before_destroy = true
  }

  tags = { Name = "${var.project}-cert" }
}

# NOTE: no aws_acm_certificate_validation resource.
#
# That resource BLOCKS until the certificate is validated. Since the DNS records
# are added by hand at Hostinger, it would sit there for as long as it takes you
# to open a browser and paste two records - and time out after 45 minutes.
#
# Instead the records are an output. You add them, then check:
#
#   aws acm describe-certificate --region us-east-1 \
#     --certificate-arn "$(terraform output -raw certificate_arn)" \
#     --query 'Certificate.Status'
#
# ISSUED means done. It usually takes a few minutes after the records resolve.
