output "certificate_arn" {
  description = "Goes on the Ingress as alb.ingress.kubernetes.io/certificate-arn."
  value       = aws_acm_certificate.this.arn
}

output "app_host" {
  value = var.app_host
}

output "api_host" {
  value = var.api_host
}

# The records to paste into Hostinger. Printed as a formatted block rather than
# raw JSON, because you are going to copy these by hand into a web form and
# reading a JSON blob for that is miserable.
#
# Add them once. ACM then renews the certificate forever, silently, as long as
# they stay in DNS. Do not delete them after validation.
output "dns_validation_records" {
  description = "CNAME records to add at Hostinger to validate the certificate."
  value = join("\n", [
    for o in aws_acm_certificate.this.domain_validation_options :
    format(
      "\n  For %s\n    Type   CNAME\n    Name   %s\n    Value  %s",
      o.domain_name,
      # Hostinger, like most DNS panels, appends the zone automatically. Pasting
      # the fully-qualified name creates
      # _abc.hello.karansiddhu.com.karansiddhu.com, which validates nothing and
      # is genuinely hard to spot.
      trimsuffix(o.resource_record_name, ".karansiddhu.com."),
      o.resource_record_value,
    )
  ])
}

output "check_status_command" {
  description = "Run this after adding the records. ISSUED means done."
  value       = "aws acm describe-certificate --region us-east-1 --certificate-arn ${aws_acm_certificate.this.arn} --query 'Certificate.Status' --output text"
}
