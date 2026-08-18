# testing-aws-magure-deploy

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
| 2 | `kind/`, `k8s/raw/` - a local cluster and hand-written manifests | in progress |
| 3 | `k8s/charts/` - the same thing as Helm charts, `k8s/raw/` deleted | not started |
| 4 | `k8s/argocd/` - GitOps | not started |
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
  raw/                 TEMPORARY, Phase 2 only. Deleted in Phase 3
  charts/              [3] one Helm chart per component
  argocd/
    bootstrap/         [4] the root app-of-apps
    applications/      [4] one Application per chart
  k8s-config/          [5] imperative bootstrap, numbered phases
    apply.sh
    env.sh.example
  validate.sh          [3] renders every chart the way ArgoCD will

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

## Phase 2 quickstart

```bash
# 1. create the local cluster (about a minute)
kind create cluster --config kind/cluster.yaml

# 2. create the namespace
kubectl apply -f k8s/raw/00-namespace.yaml

# 3. create the secret BY HAND. It is never written to a file
kubectl create secret generic db-credentials --namespace dummy-hello \
  --from-literal=POSTGRES_USER='hello' \
  --from-literal=POSTGRES_PASSWORD='<password>' \
  --from-literal=POSTGRES_DB='hello' \
  --from-literal=DATABASE_URL='postgresql+asyncpg://hello:<password>@postgres:5432/hello'

# 4. apply everything else
kubectl apply -f k8s/raw/

# 5. watch it come up
kubectl get pods -n dummy-hello -w

# 6. reach the app
kubectl port-forward -n dummy-hello svc/fe 3000:3000
# then open http://localhost:3000
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
