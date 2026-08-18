{{/*
Named templates. Define a snippet once here, `include` it wherever it is
needed. This is the Helm equivalent of the YAML anchor you used in
docker/compose.dev.yaml - same problem, same solution.

In Phase 2 these labels were written out by hand in three places per file, and
a typo in any one of them would have silently broken the Service. Now there is
one definition.

Note the values are HARDCODED, not `{{ .Chart.Name }}`. The real MagOneAI
charts do the same. Deriving them looks cleverer but means renaming the chart
directory silently changes every label, which changes the Deployment's
immutable selector, which makes the next upgrade fail.
*/}}

{{/*
Full label set. Goes on every object and on the pod template.
*/}}
{{- define "be.labels" -}}
app.kubernetes.io/name: be
app.kubernetes.io/part-of: dummy-hello
app.kubernetes.io/component: backend
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels: the subset used to MATCH pods.

Deliberately smaller than the full set, and this matters. A Deployment's
`spec.selector` is IMMUTABLE after creation. If `managed-by` were in here and
you later switched from Helm to something else, the value would change, the
selector would change, and the upgrade would be rejected outright.

Keep selectors to values that will never change.
*/}}
{{- define "be.selectorLabels" -}}
app.kubernetes.io/name: be
{{- end -}}
