# The root Application. Everything in k8s/argocd/applications/ is its child.
#
# This is the "app-of-apps" pattern: one Application whose job is to create
# other Applications. You apply THIS file, and nothing else, by hand.
#
# WHY IT EXISTS, and it is not cosmetic:
#
# ArgoCD honours argocd.argoproj.io/sync-wave only when ordering resources
# WITHIN a single sync operation. Applying the applications directory with
# `kubectl apply -f` creates N independent Applications, each with its own sync
# loop - and at that point nothing is syncing them AS RESOURCES, so every
# sync-wave annotation on them is inert. The waves read like ordering and
# provide none.
#
# For us that means be starts migrating against a Postgres that does not exist
# yet. It recovers, because Kubernetes retries, but the recovery looks like a
# crash loop to whoever is watching and hides any real failure in the noise.
#
# With this root in place the children become resources of one sync, the waves
# order them, and ArgoCD waits for each wave to be Healthy before the next.
#
# It has a second benefit that matters more day to day: adding a service is
# adding one file to k8s/argocd/applications/, and removing one is deleting
# that file. No cluster access required for either.
#
# A TEMPLATE, because the path it watches depends on where you are deploying.
# apply.sh renders it from env.sh.
#
#   PLATFORM=kind  ->  k8s/argocd/envs/kind   in-cluster Postgres, Docker Hub
#                                             images, ingress-nginx
#   PLATFORM=eks   ->  k8s/argocd/envs/eks    RDS, ECR images, AWS Load
#                                             Balancer Controller
#
# THIS IS A DELIBERATE DEVIATION from the Magure repos. They never do it:
# trinity, neo and awnic are three separate repositories, one per environment,
# and each has exactly one applications/ directory.
#
# That is the better pattern when environments are long-lived and owned by
# different people. Ours are not - kind is a free rehearsal for EKS, on the same
# app, by the same person - and running EKS around the clock to avoid one
# directory split would cost about $120 a month.
#
# The two directories are NOT copies. envs/eks/be.yaml overrides the image to
# ECR; envs/kind has a postgres Application that EKS does not, because EKS uses
# RDS. The differences are the point.
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: dummy-hello-root
  namespace: argocd
  finalizers:
    # Without this, deleting the Application leaves everything it deployed
    # running and unowned. The finalizer makes deletion cascade.
    - resources-finalizer.argocd.argoproj.io
spec:
  project: dummy-hello

  source:
    repoURL: https://github.com/KaranSiddhu/testing-aws-magure-deploy.git
    targetRevision: main
    path: k8s/argocd/envs/${PLATFORM}
    directory:
      # Flat. There are no subdirectories today, and if one is ever added it
      # should be a deliberate decision rather than silently swept in.
      recurse: false

  destination:
    server: https://kubernetes.default.svc
    # The child Application objects live here, which is why the AppProject
    # lists argocd as a permitted destination.
    namespace: argocd

  syncPolicy:
    automated:
      # prune: a file deleted from applications/ deletes its Application, and
      # that Application's own finalizer then removes what it deployed. Git is
      # genuinely the source of truth, including for removals.
      prune: true

      # selfHeal: if the live cluster drifts from git, ArgoCD corrects it.
      # This is the setting that makes `kubectl edit` pointless, and it is the
      # whole reason "do not kubectl apply a workload directly" is a rule in
      # every Magure deployment repo.
      selfHeal: true

    syncOptions:
      # Server-side apply. Field ownership is tracked by the API server, so
      # ArgoCD only fights over fields it actually manages instead of
      # overwriting the whole object.
      - ServerSideApply=true

    retry:
      limit: 5
      backoff:
        duration: 15s
        factor: 2
        maxDuration: 5m
