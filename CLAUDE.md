# testing-aws-magure-deploy - operating notes

## What this repo is

A practice deployment for `dummy-hello-app`
(`github.com/KaranSiddhu/argocd-aws`), built to learn the stack the real client
deployments use. Structure deliberately mirrors `magoneai-awnic-deploy`, which
is the AWS one.

Built phase by phase, see `../../LEARNING-ROADMAP.md`.

## Hard-won constraints

This section is the most valuable thing in the repo, and it is the reason
AWNIC's `CLAUDE.md` exists. Every entry is something that failed late, quietly,
and blamed the wrong component. **Add to it every time something surprises
you.**

- **Two build targets cannot own one image tag.** Docker 28 builds in parallel,
  so two targets exporting to the same name race and the loser fails with
  `image "...": already exists`. Exactly one thing owns a build; everything else
  references the result. Hit first in `docker/compose.dev.yaml`, then again in
  CI where both architecture jobs would have claimed `:dev`. The CI fix is to
  push by digest and tag once, in a separate merge job.

- **QEMU emulation breaks `npm`.** Building arm64 on an amd64 runner via QEMU
  killed `npm install` with `qemu: uncaught target signal 4 (Illegal
  instruction)`, then hung retrying instead of failing. Python survived it,
  Node did not. Build each architecture on a runner that IS that architecture -
  `ubuntu-24.04-arm` is free and unlimited on public repos.

- **`NEXT_PUBLIC_*` is build-time and cannot be overridden at runtime.** Next.js
  substitutes those values into the JavaScript bundle during `next build`.
  Setting one as an env var on a Deployment does nothing at all. The fix is a
  proxy route handler reading an ordinary (non-`NEXT_PUBLIC_`) variable per
  request, which is what makes one image usable in every environment.

- **A Service finds pods by LABEL, not by name.** If `spec.selector` does not
  match the pod template's labels, the Service is created successfully, has
  zero endpoints, and every connection is refused. Nothing warns you. Check
  with `kubectl get endpoints -n dummy-hello`.

- **Liveness probes must not check the database.** Failing liveness restarts the
  pod. A 30-second database blip would then restart every replica at once and
  turn a small problem into an outage. Liveness hits `/health` (touches
  nothing), readiness hits `/ready` (checks the database).

- **Postgres needs `PGDATA` pointed at a subdirectory of the volume.** Some
  storage backends create a `lost+found` at the root of a fresh volume, and
  Postgres refuses to initialise into a non-empty directory.

- **Port 5432 is taken locally.** A Homebrew PostgreSQL owns it on this Mac, so
  `docker/compose.dev.yaml` maps `5433:5432`. Only the host-side number changed;
  container-to-container traffic never touched it.

## Never

- Commit `env.sh`, a `.tfstate` file, a kubeconfig, or any rendered `.yaml`
  produced from a `.tpl`.
- Deploy a moving tag (`:dev`, `:latest`). Always pin `dev-<sha>`.
- `kubectl apply` a workload directly once ArgoCD owns it (from Phase 4).
  ArgoCD self-heals and will revert it, usually while you are still wondering
  whether the change worked.
- Leave an AWS environment running overnight. `terraform destroy` ends every
  session from Phase 6 onward.

## Conventions

- **Namespace:** `dummy-hello`
- **Labels:** the standard `app.kubernetes.io/*` set, matching what the real
  charts emit from `_helpers.tpl`
- **Layer numbering:** copied from AWNIC, with gaps so a layer can be inserted
  without renumbering
- **Secrets:** created by command in Phase 2, rendered from `env.sh` by
  `envsubst` from Phase 5, never in git either way

## Local cluster

```bash
kind create cluster --config kind/cluster.yaml   # create
kubectl config use-context kind-dummy-hello      # select
kind delete cluster --name dummy-hello           # destroy, costs nothing
```

Three nodes: one control plane, two workers. Ports 8080 and 8443 on the Mac map
to 80 and 443 on the control-plane node, ready for an Ingress later. Changing
that mapping means recreating the cluster, which is why it is set up before it
is needed.
