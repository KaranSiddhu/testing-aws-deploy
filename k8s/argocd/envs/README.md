# k8s/argocd/envs

One directory per deployment target. The root Application in `bootstrap/` points
at exactly one of them, chosen by `PLATFORM` in `k8s-config/env.sh`.

```
kind/    postgres, be, fe                     free, on your Mac
eks/     alb-controller, be, fe               real AWS, ~$4/day
```

## What actually differs

| | kind | eks |
|---|---|---|
| Database | `postgres` Application, a StatefulSet in-cluster | **no Application** - RDS, built by Terraform |
| Images | `docker.io/karansiddhu/*` (chart default) | `*.dkr.ecr.us-east-1.amazonaws.com/*` (override) |
| Ingress controller | ingress-nginx, installed by `k8s-config/06-ingress` | `aws-load-balancer-controller` Application, wave 0 |
| Routing | one Ingress, `localtest.me:8080` | two Ingresses on one ALB, real hostnames, ACM TLS |

Everything else - the charts themselves, the probes, the resources, the
migration init container, `API_INTERNAL_URL` - is identical. **The application
image is byte-identical too**: `images/mirror-to-ecr.sh` copies it, it is never
rebuilt for AWS.

## Why this split exists at all

**It is a deviation from how Magure works.** `trinity-magure-deploy`,
`neo-difc-deploy` and `magoneai-awnic-deploy` are three separate repositories,
one per environment, each with a single `applications/` directory. That is the
better pattern when environments are long-lived and owned by different teams.

Ours are not. `kind` is a free rehearsal for `eks`, on the same app, run by the
same person. Keeping EKS up around the clock to avoid one directory split would
cost roughly $120 a month.

## Working pattern

```
change a chart  ->  test on kind      free, about a minute
                ->  deploy to eks     real, costs money, do it once it works
```

Same reason you run `docker compose` before pushing to CI.

## Adding a service

Add the chart under `k8s/charts/`, then an Application in **each** environment
that should run it. Forgetting one is the obvious failure mode here, and the
symptom is simply that it is missing - nothing errors.

`k8s/validate.sh` checks the charts. It does not check that both environments
reference them.
