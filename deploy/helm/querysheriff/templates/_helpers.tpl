{{- define "querysheriff.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "querysheriff.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "querysheriff.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "querysheriff.selectorLabels" -}}
app.kubernetes.io/name: {{ include "querysheriff.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "querysheriff.labels" -}}
helm.sh/chart: {{ include "querysheriff.chart" . }}
{{ include "querysheriff.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "querysheriff.backendImage" -}}
{{- printf "%s/%s:%s" .Values.image.registry .Values.backend.image.repository (required "backend.image.tag is required" .Values.backend.image.tag) -}}
{{- end -}}

{{- define "querysheriff.frontendImage" -}}
{{- printf "%s/%s:%s" .Values.image.registry .Values.frontend.image.repository (required "frontend.image.tag is required" .Values.frontend.image.tag) -}}
{{- end -}}

{{- define "querysheriff.secretName" -}}
{{- default (printf "%s-backend" (include "querysheriff.fullname" .)) .Values.secret.name -}}
{{- end -}}

{{- define "querysheriff.origin" -}}
{{- $scheme := ternary "https" "http" .Values.ingress.tls.enabled -}}
{{- $host := required "ingress.host is required" .Values.ingress.host -}}
{{- printf "%s://%s" $scheme $host -}}
{{- end -}}

{{- define "querysheriff.apiUrl" -}}
{{- printf "%s/api" (include "querysheriff.origin" .) -}}
{{- end -}}
