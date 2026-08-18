{{- define "metrics-server.labels" -}}
app.kubernetes.io/name: metrics-server
app.kubernetes.io/part-of: magoneai
app.kubernetes.io/component: monitoring
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "metrics-server.selectorLabels" -}}
app.kubernetes.io/name: metrics-server
{{- end -}}
