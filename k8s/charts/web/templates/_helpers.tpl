{{- define "web.labels" -}}
app.kubernetes.io/name: web
app.kubernetes.io/part-of: magoneai
app.kubernetes.io/component: frontend
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "web.selectorLabels" -}}
app.kubernetes.io/name: web
{{- end -}}
