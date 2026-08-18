# The database credentials.
#
# THIS IS THE FILE THE WHOLE BOOTSTRAP LAYER EXISTS FOR.
#
# Until now you created this Secret by typing a `kubectl create secret` command
# and remembering to do it. That works exactly once, on one machine, by one
# person. It is also the step everybody forgets when rebuilding, and the failure
# is a pod stuck in CreateContainerConfigError with no obvious cause.
#
# Now the SHAPE is in git and the VALUES come from env.sh at render time.
#
#   secrets.yaml.tpl   committed. Shows what keys exist
#        |  envsubst, reading env.sh
#        v
#   secrets.yaml       gitignored. Contains the password
#        |  kubectl apply
#        v
#   the cluster
#
# ArgoCD never manages this. It cannot: the values are not in git for it to read.
# That is also why the AppProject sets `orphanedResources: warn` instead of
# pruning - to ArgoCD this Secret is an unowned resource, and pruning it would
# take the database down.
#
# In a real deployment this is where you graduate to a secrets manager. trinity
# uses HashiCorp Vault with KMS auto-unseal; AWNIC uses External Secrets
# Operator pulling from AWS Secrets Manager. Both replace this file. Neither
# changes the principle: values never enter git.
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
  namespace: ${NS}
type: Opaque

# stringData, not data.
#
# `data` requires every value to be base64-encoded by hand, which is tedious,
# easy to get wrong, and hides typos until a pod fails to start. `stringData`
# takes plain text and lets the API server do the encoding. It is write-only:
# reading the Secret back shows a normal base64 `data` block.
#
# Note that base64 is ENCODING, not encryption. Anyone who can read Secrets in
# this namespace can decode them instantly. Kubernetes Secrets keep values out
# of manifests and out of environment listings; they are not a vault.
stringData:
  POSTGRES_USER: "${POSTGRES_USER}"
  POSTGRES_PASSWORD: "${POSTGRES_PASSWORD}"
  POSTGRES_DB: "${POSTGRES_DB}"

  # Assembled by apply.sh, NOT hardcoded here. That matters, because the two
  # platforms need completely different values:
  #
  #   kind  postgresql+asyncpg://<user>:<pw>@postgres:5432/<db>
  #         "postgres" is a Service in this namespace.
  #
  #   eks   postgresql+asyncpg://<user>:<pw>@<rds-endpoint>:5432/<db>?sslmode=require
  #         taken from DATABASE_URL_OVERRIDE in env.sh, which comes from
  #         `terraform output -raw database_url`. RDS enforces TLS, so
  #         sslmode=require is not optional.
  #
  # This line previously hardcoded "@postgres:5432" and ignored the override
  # entirely. apply.sh reported "DATABASE_URL: from DATABASE_URL_OVERRIDE" while
  # rendering the kind value anyway - the script was right and the template was
  # not. On EKS the pod then failed with:
  #
  #     socket.gaierror: [Errno -2] Name or service not known
  #
  # which reads as broken cluster DNS rather than a wrong hostname.
  #
  # The lesson is worth more than the fix: a log line saying it did the right
  # thing is not evidence that it did. Check the artefact, not the narration -
  # `kubectl get secret db-credentials -o jsonpath='{.data.DATABASE_URL}' |
  # base64 -d` would have shown it immediately.
  #
  # The password inside is already URL-encoded, either by apply.sh or by
  # Terraform's urlencode() in the 30-data output.
  DATABASE_URL: "${DATABASE_URL}"
