# Routes traffic from outside the cluster to the frontend Service.
#
# After this, `kubectl port-forward` is no longer needed:
#
#     http://${APP_HOST}:8080
#
# The 8080 comes from kind/cluster.yaml mapping host port 8080 to port 80 on the
# ingress-ready node. On a real cluster it would just be port 80/443 behind a
# load balancer.
#
# WHY ONLY THE FRONTEND IS EXPOSED, and this is a deliberate design decision:
#
# The backend has no Ingress and does not need one. The browser calls /api on
# the frontend's own origin, and the Next.js server proxies onward to
# http://be:8000 inside the cluster. So `be` stays a ClusterIP Service with no
# route from outside at all.
#
# That is a smaller attack surface for free: there is no external path to the
# API, no authentication to get wrong on it, and no CORS configuration to
# maintain. It is the payoff for the proxy route we built back in Phase 1.
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: fe
  namespace: ${NS}
  labels:
    app.kubernetes.io/name: fe
    app.kubernetes.io/part-of: ${NS}
spec:
  # WHICH controller should act on this object. An Ingress with no
  # ingressClassName is ignored by every controller unless one is marked as the
  # cluster default - and the symptom is an Ingress that exists, looks correct,
  # and never receives a single request.
  ingressClassName: nginx

  rules:
    - host: ${APP_HOST}
      http:
        paths:
          - path: /
            # Prefix: match this path and everything under it.
            # Exact would match only "/" and nothing else.
            pathType: Prefix
            backend:
              service:
                name: fe
                port:
                  # By NAME, not number. The Service defines `name: http`, so if
                  # the port ever changes this rule follows automatically.
                  name: http
