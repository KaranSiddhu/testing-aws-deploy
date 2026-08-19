# testing-aws-deploy

Practice deployment repo. It deploys **dummy-hello-app**
(`github.com/KaranSiddhu/argocd-aws`) and exists to learn the same stack the
real client deployments use: Terraform, Helm, ArgoCD, EKS.

It intentionally mirrors the structure of `trinity-magure-deploy`,
`neo-difc-deploy` and `magoneai-awnic-deploy`. AWNIC is the closest model,
because it is the AWS one.

The application source lives in a separate repo. **This repo contains no
application code** - it names images and describes how to run them. That split
is the point.

## Status

Built phase by phase. See `../../LEARNING-ROADMAP.md` for the full plan.

| Phase | Adds | Status |
|---|---|---|
| 2 | `kind/`, `k8s/raw/` - a local cluster and hand-written manifests | done |
| 3 | `k8s/charts/` + `validate.sh` - the same objects as Helm charts, `k8s/raw/` deleted | done |
| 4 | `k8s/argocd/` - AppProject, app-of-apps, one Application per chart | done |
| 5 | `k8s/k8s-config/` - imperative bootstrap, ingress, `apply.sh` | done |
| 5 | `k8s/k8s-config/` - imperative bootstrap | not started |
| 6 | `terraform/` - VPC, EKS, RDS | not started |
| 7 | `images/` - ECR mirroring, and EKS deployment | not started |

## Layout

Directories appear as the phase that needs them arrives. Nothing is created
empty.

```
kind/                  local practice cluster (no equivalent in the real repos)
  cluster.yaml

k8s/
  charts/              one Helm chart per component: be, fe, postgres
  argocd/
    bootstrap/         [4] the root app-of-apps
    applications/      [4] one Application per chart
  k8s-config/          imperative bootstrap, run by hand, in order
    00-foundation      namespace + db-credentials Secret
    06-ingress         ingress-nginx
    07-routes          the app's Ingress
    10-argocd          ArgoCD install + handover to GitOps
    apply.sh
    env.sh.example
  validate.sh          renders every chart the way ArgoCD will

terraform/             [6]
  modules/aws/         reusable, one concern each
  aws/                 layers, applied in numeric order
    00-prereq          state bucket. LOCAL backend, it creates the remote one
    10-network         vpc
    20-cluster         eks + node group
    30-data            rds + ecr
    40-access          IRSA roles

images/                [7] image manifest, ECR mirror, digest stamping
```

The gaps in the layer numbers are deliberate, copied from AWNIC: a new layer
can be inserted without renumbering everything after it.

## Cold start

```bash
kind create cluster --config kind/cluster.yaml

cd k8s/k8s-config
cp env.sh.example env.sh        # fill in POSTGRES_PASSWORD
./apply.sh

kubectl get applications -n argocd -w
```

Then:

- app: http://dummy-hello.localtest.me:8080
- argocd: http://argocd.localtest.me:8080

`localtest.me` resolves to `127.0.0.1`, so no `/etc/hosts` editing is needed.
Port 8080 is mapped to the cluster's port 80 by `kind/cluster.yaml`.

ArgoCD admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

`apply.sh` handles the namespace, the `db-credentials` Secret, ingress-nginx,
ArgoCD, and the handover to GitOps. Full detail in
`k8s/k8s-config/README.md`.

Tear it all down with `kind delete cluster --name dummy-hello`. Nothing outside
Docker is touched.

## Deploying

Edit `image.tag` in the chart's `values.yaml`, commit, push. ArgoCD does the
rest. Never `helm --set`, never `kubectl apply` a workload - ArgoCD self-heals
and reverts both. See `CLAUDE.md`.

Before committing:

```bash
./k8s/validate.sh
```

Tear it all down with `kind delete cluster --name dummy-hello`. Nothing outside
Docker is touched.

## Images

Built by GitHub Actions in the app repo on every push to `main`, and published
to Docker Hub:

```
docker.io/karansiddhu/dummy-hello-be:dev-<short-sha>
docker.io/karansiddhu/dummy-hello-fe:dev-<short-sha>
```

Manifests here always pin `dev-<sha>`, never the moving `dev` tag. To deploy a
new build, change the tag and re-apply. From Phase 4 that becomes: change the
tag, commit, and ArgoCD does the rest.

## Conventions

- **Namespace:** `dummy-hello`
- **Labels:** the standard `app.kubernetes.io/*` set, matching what the real
  charts emit from their `_helpers.tpl`
- **Secrets:** never committed. Created by command in Phase 2, rendered from
  `env.sh` by `envsubst` from Phase 5
- **Image tags:** always pinned to a commit
