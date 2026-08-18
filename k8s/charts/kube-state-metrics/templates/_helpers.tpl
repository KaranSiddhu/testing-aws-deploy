{{- define "ksm.labels" -}}
app.kubernetes.io/name: kube-state-metrics
app.kubernetes.io/part-of: magoneai
app.kubernetes.io/component: monitoring
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "ksm.selectorLabels" -}}
app.kubernetes.io/name: kube-state-metrics
{{- end -}}
