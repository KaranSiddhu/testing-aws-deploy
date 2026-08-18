# 06-ingress

Installs the ingress controller. No manifests live here: `apply.sh` applies the
upstream kind-provider manifest, pinned to `$INGRESS_NGINX_VERSION` from
`env.sh`.

## What an ingress controller actually is

A **Service** gets you an address inside the cluster. Nothing more. Reaching the
app from outside has meant `kubectl port-forward`, which is one tunnel, for one
service, for as long as you keep the terminal open.

An **Ingress** is a routing rule: "requests for this hostname and path go to
that Service". But an Ingress object on its own does nothing at all - it is
data. An **ingress controller** is the pod that reads those objects and
configures a real proxy to match.

That split catches people out: you create an Ingress, `kubectl get ingress`
shows it, and nothing works, because no controller is installed to act on it.

## Why the kind-specific manifest

The generic install expects a cloud load balancer to hand it an external IP. On
kind there is no cloud, so the kind variant instead runs the controller with
`hostPort` on the node labelled `ingress-ready=true` - which
`kind/cluster.yaml` sets, and whose ports 80 and 443 are mapped to 8080 and 8443
on your Mac.

That is why the port mapping had to be decided back in Phase 2: changing it
means deleting and recreating the cluster.

## ingress-nginx is retired

The Kubernetes project **retired ingress-nginx on 2026-03-23**. The repository is
archived: no further releases, and no security patches ever.
`controller-v1.15.1` is the final release.

It is used here for two reasons:

1. This cluster is local-only and not reachable from the internet, so the
   unpatched-vulnerability risk does not apply.
2. `trinity-magure-deploy` and `neo-difc-deploy` still run it in production, so
   it is what you will actually meet at work.

`magoneai-awnic-deploy` does **not**, and its README says why in one line:
"ingress-nginx was archived by the Kubernetes project on 2026-03-23 and gets no
security patches". It uses the AWS Load Balancer Controller instead, which is
what Phase 7 does here too.

The Kubernetes project's recommended direction is the **Gateway API**, with
Envoy Gateway, Traefik or Cilium as the controller. Worth knowing; not worth
learning at the same time as everything else.

**The Ingress resource itself is not retired.** Only this controller is. What
you write in `07-routes/` transfers unchanged to any other controller.
