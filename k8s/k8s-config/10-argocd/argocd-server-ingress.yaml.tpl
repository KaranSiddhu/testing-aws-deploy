# Reach the ArgoCD UI at http://${ARGOCD_HOST}:8080 instead of running
# `kubectl port-forward svc/argocd-server -n argocd 8081:443` every time.
#
# Works because kustomization.yaml sets server.insecure=true, so argocd-server
# serves plain HTTP and the ingress controller can talk to it normally. Without
# that patch this Ingress produces a redirect loop or a 502 with nothing in the
# logs about TLS.
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
spec:
  ingressClassName: nginx
  rules:
    - host: ${ARGOCD_HOST}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  name: http
