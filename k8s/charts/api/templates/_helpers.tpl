{{- define "api.labels" -}}
app.kubernetes.io/name: api
app.kubernetes.io/part-of: magoneai
app.kubernetes.io/component: api
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "api.selectorLabels" -}}
app.kubernetes.io/name: api
{{- end -}}
