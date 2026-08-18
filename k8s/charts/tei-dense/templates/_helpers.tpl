{{- define "tei-dense.labels" -}}
app.kubernetes.io/name: tei-dense
app.kubernetes.io/part-of: magoneai
app.kubernetes.io/component: tei-dense
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "tei-dense.selectorLabels" -}}
app.kubernetes.io/name: tei-dense
{{- end -}}
