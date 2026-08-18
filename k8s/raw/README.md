# k8s/raw — temporary, Phase 2 only

**This directory is deleted in Phase 3.** It has no equivalent in
`trinity-magure-deploy`, `neo-difc-deploy` or `magoneai-awnic-deploy`, all of
which went straight to Helm charts.

It exists for one reason: you have to write Kubernetes YAML by hand once before
Helm makes any sense. Otherwise Helm is just a templating language producing
output you cannot read.

## What is here

| File | Objects |
|---|---|
| `00-namespace.yaml` | Namespace |
| `10-postgres.yaml` | headless Service, StatefulSet, PersistentVolumeClaim |
| `20-be.yaml` | Service, Deployment with a migration initContainer |
| `30-fe.yaml` | Service, Deployment |

The number prefixes control apply order. `kubectl apply -f` processes files
alphabetically, and the Namespace has to exist before anything can be created
inside it.

## What is deliberately NOT here

**The Secret.** The database password is created with a command, never written
to a file:

```bash
kubectl create secret generic db-credentials --namespace dummy-hello \
  --from-literal=POSTGRES_USER='hello' \
  --from-literal=POSTGRES_PASSWORD='<password>' \
  --from-literal=POSTGRES_DB='hello' \
  --from-literal=DATABASE_URL='postgresql+asyncpg://hello:<password>@postgres:5432/hello'
```

This is the honest, awkward version of secret handling. Phase 5 replaces it
with the `env.sh` + `envsubst` pattern the real repos use, which keeps the
*shape* of a secret in git and the *values* out of it.

## The thing to notice

Open `20-be.yaml` and `30-fe.yaml` side by side. They are roughly 80%
identical: same labels repeated in three places each, same probe structure,
same resource block, same security context. The real differences are a name, an
image, a port and two environment variables.

Two components already feels wasteful. The real deployments run about 27. That
is the problem Helm exists to solve, and Phase 3 is where you solve it.
