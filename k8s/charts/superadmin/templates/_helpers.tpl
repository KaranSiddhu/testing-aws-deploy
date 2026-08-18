{{- define "superadmin.labels" -}}
app.kubernetes.io/name: superadmin
app.kubernetes.io/part-of: magoneai
app.kubernetes.io/component: frontend
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "superadmin.selectorLabels" -}}
app.kubernetes.io/name: superadmin
{{- end -}}
