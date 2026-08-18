{{- define "temporal-ui.labels" -}}
app.kubernetes.io/name: temporal-ui
app.kubernetes.io/part-of: magoneai
app.kubernetes.io/component: temporal-ui
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "temporal-ui.selectorLabels" -}}
app.kubernetes.io/component: temporal-ui
{{- end -}}
