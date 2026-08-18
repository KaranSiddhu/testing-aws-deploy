{{- define "loki.labels" -}}
app.kubernetes.io/name: loki
app.kubernetes.io/part-of: magoneai
app.kubernetes.io/component: monitoring
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "loki.selectorLabels" -}}
app.kubernetes.io/name: loki
{{- end -}}
