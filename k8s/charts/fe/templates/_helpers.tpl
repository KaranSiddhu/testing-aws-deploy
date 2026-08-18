{{/*
Deliberately a near-copy of charts/be/templates/_helpers.tpl, with "be" swapped
for "fe".

THIS IS THE HONEST LIMITATION OF HELM, and it is worth sitting with for a
moment. Helm removes duplication INSIDE a chart. It does not remove duplication
BETWEEN charts. Your company lives with about 20 near-identical _helpers.tpl
files for exactly this reason.

Two ways out exist, and both have a cost:

  - A LIBRARY CHART (Chart.yaml `type: library`) holding shared templates that
    other charts import. Removes the copy, adds a dependency to version and
    keep in step. Worth it at roughly 10+ charts.

  - A GENERIC CHART driven by one values file per instance. This is what
    charts/mcp-server does in the real repos: ONE chart, 20 values files in
    mcps/, deployed by an ApplicationSet. Perfect when the things really are
    the same shape.

`be` and `fe` are NOT the same shape: one has a migration init container, a
database secret and two probe paths; the other has none of that. Forcing them
into one generic chart would mean a values file full of `enableInitContainer:
false` toggles, which is harder to read than two honest copies.

Duplication is cheaper than the wrong abstraction. Reach for the generic chart
when the shapes genuinely converge, not before.
*/}}

{{- define "fe.labels" -}}
app.kubernetes.io/name: fe
app.kubernetes.io/part-of: dummy-hello
app.kubernetes.io/component: frontend
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "fe.selectorLabels" -}}
app.kubernetes.io/name: fe
{{- end -}}
