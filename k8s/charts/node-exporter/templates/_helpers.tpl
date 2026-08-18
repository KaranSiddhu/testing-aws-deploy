{{- define "node-exporter.labels" -}}
app.kubernetes.io/name: node-exporter
app.kubernetes.io/part-of: magoneai
app.kubernetes.io/component: monitoring
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "node-exporter.selectorLabels" -}}
app.kubernetes.io/name: node-exporter
{{- end -}}
