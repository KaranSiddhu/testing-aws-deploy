{{- define "prometheus.labels" -}}
app.kubernetes.io/name: prometheus
app.kubernetes.io/part-of: magoneai
app.kubernetes.io/component: monitoring
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "prometheus.selectorLabels" -}}
app.kubernetes.io/name: prometheus
{{- end -}}
