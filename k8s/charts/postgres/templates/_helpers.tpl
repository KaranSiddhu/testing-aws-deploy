{{- define "postgres.labels" -}}
app.kubernetes.io/name: postgres
app.kubernetes.io/part-of: dummy-hello
app.kubernetes.io/component: database
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "postgres.selectorLabels" -}}
app.kubernetes.io/name: postgres
{{- end -}}
