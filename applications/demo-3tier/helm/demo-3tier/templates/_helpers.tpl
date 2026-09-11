{{/*
Common naming and labelling helpers for demo-3tier.
The resource names intentionally stay stable because the existing lab scripts,
OpenShift Route, Services and PVC checks already expect these names.
*/}}
{{- define "demo3tier.name" -}}
demo-3tier
{{- end -}}

{{- define "demo3tier.fullname" -}}
{{- default "demo-3tier" .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "demo3tier.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" -}}
{{- end -}}

{{- define "demo3tier.commonLabels" -}}
app.kubernetes.io/name: {{ include "demo3tier.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ include "demo3tier.chart" . }}
app.kubernetes.io/part-of: demo-3tier
{{- end -}}

{{- define "demo3tier.frontendLabels" -}}
{{ include "demo3tier.commonLabels" . }}
app: demo-frontend
tier: frontend
app.kubernetes.io/component: frontend
{{- end -}}

{{- define "demo3tier.backendLabels" -}}
{{ include "demo3tier.commonLabels" . }}
app: demo-backend
tier: backend
app.kubernetes.io/component: backend
{{- end -}}

{{- define "demo3tier.postgresLabels" -}}
{{ include "demo3tier.commonLabels" . }}
app: demo-postgres
tier: database
app.kubernetes.io/component: database
{{- end -}}
