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

- **`runAsNonRoot: true` requires a numeric `runAsUser`.** The kubelet checks
  "is this non-root?" before starting the container and never reads the image's
  `/etc/passwd`. A Dockerfile that says `USER hello` gives it a name it cannot
  resolve, so it fails closed with `CreateContainerConfigError: container has
  runAsNonRoot and image has non-numeric user (hello)`. The failure is at
  container CREATION, so there are no application logs and `kubectl logs`
  returns nothing useful - the message is only in `kubectl describe pod` or
  `.status.containerStatuses[].state.waiting.message`. Fix in the manifest with
  `runAsUser: <uid>`, or better, at the source with `USER 1000` in the
  Dockerfile.

- **Kubernetes has no `depends_on`.** The migration initContainer failed three
  times with `Init:Error` and `Init:CrashLoopBackOff` while Postgres was still
  starting, then succeeded on its own. That is the design: everything retries
  with backoff until its dependency is ready, rather than being ordered up
  front, because a database can restart at 3am and nothing can rely on startup
  order anyway. A CrashLoopBackOff during startup is not automatically a bug -
  check whether it is converging before investigating.

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

- **Helm will not adopt resources created by `kubectl`.** It only takes
  ownership of an object that ALREADY carries the label
  `app.kubernetes.io/managed-by: Helm` and the annotations
  `meta.helm.sh/release-name` and `meta.helm.sh/release-namespace`, otherwise
  `helm install` aborts with `invalid ownership metadata`. That is a safety
  feature: without it, Helm could silently take over something another tool
  manages and a later `helm uninstall` would delete resources Helm never
  created. Either delete the objects first (data in a PVC survives - the PVCs
  from `volumeClaimTemplates` carry no ownerReferences and default to `Retain`)
  or patch the label and annotations on to adopt them with no downtime.

- **A Helm template comment cannot contain its own closing delimiter.** There is
  no nesting and no escaping, so writing the delimiter inside the block - even
  as an example in documentation - ends the comment there, and everything after
  it becomes literal template output. The error is
  `YAML parse error: cannot unmarshal string into Go value of type
  util.SimpleHead`, which says nothing about comments. Read that message as
  "Helm produced something that is not a Kubernetes object".

- **`helm upgrade` silently switches value strategy depending on `--set`.** Pass
  `--set` and it resets to the chart's `values.yaml` then applies the override.
  Pass nothing and it REUSES the previous release's user-supplied values, so a
  stale override from an earlier `--set` wins and your edited `values.yaml` is
  ignored. Helm reports "Upgrade complete" and exits 0 while the cluster runs a
  different image than the file says: a green deploy that did not deploy. Check
  with `helm get values <release>` (without `--all`, which shows the merged
  result and hides the problem), and fix with `--reset-values`. This is the
  strongest practical argument for GitOps: ArgoCD re-renders the chart from Git
  every sync, so there is no stored user-values layer for drift to hide in.

- **A template comment is stripped, a `#` comment is not.** `{{- /* ... */}}`
  style blocks never reach the cluster; `#` lines are rendered into the manifest
  and show up in `helm get manifest`. Both are fine, but choose deliberately:
  notes for whoever edits the chart in the first, notes for whoever debugs the
  running object in the second. Also note that a template comment placed inside
  a mapping leaves the indentation before it behind as a stray blank line in the
  output - keep explanatory blocks at the top of the file.

- **Port 5432 is taken locally.** A Homebrew PostgreSQL owns it on this Mac, so
  `docker/compose.dev.yaml` maps `5433:5432`. Only the host-side number changed;
  container-to-container traffic never touched it.

## Never

- Commit `env.sh`, a `.tfstate` file, a kubeconfig, or any rendered `.yaml`
  produced from a `.tpl`.
- Deploy a moving tag (`:dev`, `:latest`). Always pin `dev-<sha>`.
- Use `helm --set` for a real deploy. It stores a sticky override on the release
  that silently beats `values.yaml` on every later upgrade. `--set` is for
  throwaway experiments; a real change edits `values.yaml` and is committed, so
  the diff is reviewable and git records what is running.
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

## Charts

Three charts, one per component: `be`, `fe`, `postgres`.

`values.yaml` holds the image repository and tag, and almost nothing else.
Replicas, env, probes, resources and the migration init container are all
hardcoded in `templates/`. That is deliberate and it matches the real MagOneAI
charts, whose `charts/api/values.yaml` is two lines with a comment saying why:
the image is the only thing that meaningfully changes between deploys. A knob
you never turn is a place for a bug and one more thing to read past.

`_helpers.tpl` hardcodes the label values rather than deriving them from
`{{ .Chart.Name }}`. Deriving looks cleverer but means renaming the chart
directory changes the Deployment's selector, which is immutable, and the next
upgrade is rejected outright.

Selector labels are deliberately a subset of the full label set, for the same
reason: `managed-by` can change, and a changed selector is an unfixable upgrade.

Before every commit:

```bash
./k8s/validate.sh          # renders every chart the way ArgoCD will
```

It needs no cluster. If PyYAML is not installed it falls back to
`uv run --with pyyaml`, which builds a throwaway environment and installs
nothing (a deliberate deviation from AWNIC's version, which just requires it).

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
