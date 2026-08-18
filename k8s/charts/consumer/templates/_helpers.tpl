{{- define "consumer.labels" -}}
app.kubernetes.io/name: consumer
app.kubernetes.io/part-of: magoneai
app.kubernetes.io/component: frontend
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "consumer.selectorLabels" -}}
app.kubernetes.io/name: consumer
{{- end -}}
