{{- define "kb-worker.labels" -}}
app.kubernetes.io/name: kb-worker
app.kubernetes.io/part-of: magoneai
app.kubernetes.io/component: worker
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "kb-worker.selectorLabels" -}}
app.kubernetes.io/name: kb-worker
{{- end -}}
