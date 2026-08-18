# Routes for EKS. Two Ingress objects, ONE load balancer.
#
# Compare with ingress-nginx.yaml.tpl: the `rules` are nearly identical, because
# the Ingress RESOURCE is standard Kubernetes. Everything AWS-specific lives in
# annotations. That portability is the reason the retirement of ingress-nginx
# does not invalidate what you learned on kind.
#
# ONE ALB, NOT TWO. Both Ingresses share
# alb.ingress.kubernetes.io/group.name, which tells the controller to merge them
# onto a single load balancer. Without it you would get two ALBs at $0.55/day
# each, two DNS targets to manage, and two certificates to attach.

---
# =============================================================================
# The frontend: hello.karansiddhu.com
# =============================================================================
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: fe
  namespace: ${NS}
  labels:
    app.kubernetes.io/name: fe
    app.kubernetes.io/part-of: ${NS}
  annotations:
    # Merge with any other Ingress sharing this group name.
    alb.ingress.kubernetes.io/group.name: ${NS}

    # internet-facing, not internal. AWNIC's is internal, which is why it cannot
    # use ACM-issued certificates: ACM validates by reaching the name publicly,
    # and an internal-only name is not reachable. They import a client cert
    # instead. Ours are public, so ACM can simply issue.
    alb.ingress.kubernetes.io/scheme: internet-facing

    # Register POD ips directly as targets, rather than node ports.
    #
    # Works because the VPC CNI gives every pod a real VPC IP address. It means
    # traffic goes ALB -> pod in one hop instead of ALB -> node -> kube-proxy ->
    # pod, and a pod that fails its readiness probe is pulled from the target
    # group immediately.
    alb.ingress.kubernetes.io/target-type: ip

    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'

    # The ALB terminates TLS with this certificate. No cert-manager, no ACME
    # challenge, no renewal job: ACM renews it automatically forever, as long as
    # the validation CNAMEs stay in DNS.
    alb.ingress.kubernetes.io/certificate-arn: ${CERT_ARN}

    # Redirect plain HTTP to HTTPS at the load balancer, so no request reaches
    # the application unencrypted.
    alb.ingress.kubernetes.io/ssl-redirect: "443"

    # Health check for the target group. This is SEPARATE from the Kubernetes
    # readiness probe and easy to forget: Kubernetes deciding a pod is ready
    # does not make the ALB agree. The default checks "/" which works here, but
    # being explicit costs nothing.
    alb.ingress.kubernetes.io/healthcheck-path: /
spec:
  ingressClassName: alb
  rules:
    - host: ${APP_HOST}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: fe
                port:
                  name: http

---
# =============================================================================
# The backend: api-hello.karansiddhu.com
#
# A SECOND DOOR, for you, not for the application.
#
# The frontend still calls /api on its own origin, and the Next.js server
# proxies inward to http://be:8000. That is what keeps the frontend image free
# of any environment-specific address, and keeps CORS out of the picture
# entirely.
#
# This host exists so that YOU can reach the API directly:
#
#   https://api-hello.karansiddhu.com/docs     FastAPI's interactive page
#   curl https://api-hello.karansiddhu.com/health
#
# If the browser called this host instead, two things we deliberately removed
# would come straight back: a build-time NEXT_PUBLIC_ URL (so one image per
# environment) and cross-origin requests (so CORS).
# =============================================================================
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: be
  namespace: ${NS}
  labels:
    app.kubernetes.io/name: be
    app.kubernetes.io/part-of: ${NS}
  annotations:
    # Same group name as above. This is what merges the two onto one ALB.
    alb.ingress.kubernetes.io/group.name: ${NS}
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
    alb.ingress.kubernetes.io/certificate-arn: ${CERT_ARN}
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    # /health, not /. The API has no page at the root, so the default check
    # would get a 404 and the target group would never come up healthy - with
    # the pods themselves perfectly fine.
    alb.ingress.kubernetes.io/healthcheck-path: /health
spec:
  ingressClassName: alb
  rules:
    - host: ${API_HOST}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: be
                port:
                  name: http
