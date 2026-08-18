# k8s-config — the imperative bootstrap

Everything that must exist **before** ArgoCD can do anything. Run once, by hand,
in order.

```bash
cp env.sh.example env.sh     # then fill in POSTGRES_PASSWORD
./apply.sh
```

## Why this layer exists

GitOps cannot bootstrap itself:

| Problem | Why ArgoCD cannot solve it |
|---|---|
| ArgoCD must be installed | ArgoCD cannot install ArgoCD |
| The DB password must exist | it is not in git, so ArgoCD cannot read it |
| The namespace must exist | everything else goes inside it |
| The AppProject must exist | an Application naming a missing project never syncs |

So there is a hand-run layer underneath the declarative one. Every Magure
deployment repo has this same directory, with the same numbered shape.

## Phases

| Phase | Does | Notes |
|---|---|---|
| `00-foundation` | namespace, `db-credentials` Secret | the only place a secret is written |
| `06-ingress` | ingress-nginx `controller-v1.15.1` | kind-provider manifest, see its README |
| `10-argocd` | ArgoCD `v3.5.1`, AppProject, root Application, ArgoCD Ingress | hands over to GitOps |
| `07-routes` | the app's Ingress | runs after 10, because it points at a Service ArgoCD creates |

Run order is `00 06 10 07`, not numeric order. The numbers name a *concern*, not
a position, so a phase can move without renumbering. Trinity's real order is
`00 db 01 06 10 02 03 04 07 09` for the same reason.

Selected phases only:

```bash
./apply.sh 00 10
```

## The `.tpl` pattern

```
secrets.yaml.tpl    committed. Shows which keys exist
     |  envsubst, reading env.sh
     v
secrets.yaml        gitignored. Contains the password
     |  kubectl apply
     v
the cluster
```

The **shape** of the config is public, the **values** are not. `env.sh.example`
is committed so anyone cloning the repo knows exactly what to supply.

Rendered outputs are listed one by one in `.gitignore` rather than matched by a
glob. Adding a template is then a two-line change, and you cannot silently
forget the second line.

## Two things `apply.sh` does that are easy to skip

**It validates every variable before rendering anything.** `envsubst` renders an
unset variable as an *empty string* and exits 0. A typo'd `POSTGRES_PASSWORD`
would produce a Secret with a blank password, apply cleanly, and fail much later
as an auth error that points at the database instead of at `env.sh`.

**It URL-encodes the password** before building `DATABASE_URL`. A raw `@` or `#`
truncates the URL, and the error you get is `could not translate host name`,
which sends you looking at DNS.

## It is idempotent

Re-run it any time. That is what makes it a recovery tool rather than a
first-day script, and it is what Phase 8 (destroy and rebuild from zero)
depends on.

## What is NOT here

Workloads. Once `apply.sh` finishes, ArgoCD owns everything in
`k8s/argocd/applications/`. Do not `kubectl apply` a workload directly - ArgoCD
self-heals and reverts it.

## Cold start, end to end

```bash
kind create cluster --config kind/cluster.yaml
cd k8s/k8s-config
cp env.sh.example env.sh          # fill in POSTGRES_PASSWORD
./apply.sh
kubectl get applications -n argocd -w
```

Then:

- app: http://dummy-hello.localtest.me:8080
- argocd: http://argocd.localtest.me:8080

`localtest.me` resolves to `127.0.0.1`, so no `/etc/hosts` editing. Port 8080
comes from `kind/cluster.yaml`.
