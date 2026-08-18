{{/*
NOTE: existing manifest uses ONLY `app.kubernetes.io/component: redis` in
selectors (no `name` label). Selector fields are immutable post-creation
on a StatefulSet — must preserve exactly to avoid sync failure on adoption.
*/}}
{{- define "redis.labels" -}}
app.kubernetes.io/part-of: magoneai
app.kubernetes.io/component: redis
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "redis.selectorLabels" -}}
app.kubernetes.io/component: redis
{{- end -}}
