{{- define "grafana.labels" -}}
app.kubernetes.io/name: grafana
app.kubernetes.io/part-of: magoneai
app.kubernetes.io/component: monitoring
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "grafana.selectorLabels" -}}
app.kubernetes.io/name: grafana
{{- end -}}
