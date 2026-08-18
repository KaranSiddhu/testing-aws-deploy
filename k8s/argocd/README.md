# k8s/argocd

ArgoCD owns everything inside the cluster from here on.

```
bootstrap/
  00-project.yaml       AppProject: which repo, which namespaces, which kinds
  01-app-of-apps.yaml   the root Application. The ONLY file applied by hand
applications/
  postgres.yaml         sync-wave 1
  be.yaml               sync-wave 2
  fe.yaml               sync-wave 3
```

## How it fits together

```
you: git push
        |
        v
   GitHub repo
        |  polled / webhooked
        v
   dummy-hello-root  (Application, watches applications/)
        |  creates
        +---> postgres  (Application, renders k8s/charts/postgres)
        +---> be        (Application, renders k8s/charts/be)
        +---> fe        (Application, renders k8s/charts/fe)
                            |  applies
                            v
                     the dummy-hello namespace
```

ArgoCD renders each chart with its own bundled Helm. It never runs
`helm install`, so there is no Helm release and no stored user-supplied values.
The Phase 3 drift bug, where a stale `--set` silently beat `values.yaml`, has
nowhere to live.

## Bootstrapping

Only ever apply the two bootstrap files, in order:

```bash
kubectl apply -f k8s/argocd/bootstrap/00-project.yaml
kubectl apply -f k8s/argocd/bootstrap/01-app-of-apps.yaml
```

**Do not `kubectl apply -f k8s/argocd/applications/`.** It appears to work and
quietly breaks ordering: sync-waves are only honoured for resources within a
single sync operation, so Applications created directly by kubectl each get
their own independent sync loop and every wave annotation becomes inert. AWNIC's
`install.sh` applies the root and nothing else for exactly this reason.

## Adding or removing a service

Add: drop a new file in `applications/`, commit, push.
Remove: delete the file, commit, push. `prune: true` on the root deletes the
Application, and its finalizer removes what it deployed.

Neither needs cluster access.

## Deploying a new image

Edit `image.tag` in the chart's `values.yaml`, commit, push. That is the whole
deploy. Never `kubectl set image`, never `helm upgrade` - `selfHeal: true`
reverts both, usually while you are still wondering whether it worked.

## What is deliberately NOT here

The `db-credentials` Secret. It is created by hand and never committed, which
is why the AppProject sets `orphanedResources: warn` rather than pruning
resources no Application owns. Phase 5 replaces the manual step with the
`env.sh` + `envsubst` pattern the real repos use.
