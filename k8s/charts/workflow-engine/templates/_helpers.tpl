{{- define "workflow-engine.labels" -}}
app.kubernetes.io/name: workflow-engine
app.kubernetes.io/part-of: magoneai
app.kubernetes.io/component: worker
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "workflow-engine.selectorLabels" -}}
app.kubernetes.io/name: workflow-engine
{{- end -}}
