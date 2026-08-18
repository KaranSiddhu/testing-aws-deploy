{{/*
NOTE: existing manifest uses ONLY `app.kubernetes.io/component: qdrant` in
selectors (no `name` label). StatefulSet selector immutability — must
preserve exactly to avoid sync failure on adoption.
*/}}
{{- define "qdrant.labels" -}}
app.kubernetes.io/part-of: magoneai
app.kubernetes.io/component: qdrant
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "qdrant.selectorLabels" -}}
app.kubernetes.io/component: qdrant
{{- end -}}
