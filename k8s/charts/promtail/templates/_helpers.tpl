{{- define "promtail.labels" -}}
app.kubernetes.io/name: promtail
app.kubernetes.io/part-of: magoneai
app.kubernetes.io/component: monitoring
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "promtail.selectorLabels" -}}
app.kubernetes.io/name: promtail
{{- end -}}

{{- define "promtail.rbacLabels" -}}
app.kubernetes.io/part-of: magoneai
app.kubernetes.io/component: monitoring
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
