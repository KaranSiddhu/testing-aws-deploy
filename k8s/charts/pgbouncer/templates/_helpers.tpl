{{- define "pgbouncer.labels" -}}
app.kubernetes.io/name: pgbouncer
app.kubernetes.io/part-of: magoneai
app.kubernetes.io/component: infra
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "pgbouncer.selectorLabels" -}}
app.kubernetes.io/name: pgbouncer
{{- end -}}
