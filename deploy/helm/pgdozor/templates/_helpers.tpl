{{- define "pgdozor.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "pgdozor.fullname" -}}
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

{{- define "pgdozor.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "pgdozor.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pgdozor.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "pgdozor.labels" -}}
helm.sh/chart: {{ include "pgdozor.chart" . }}
{{ include "pgdozor.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "pgdozor.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "pgdozor.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "pgdozor.backendImage" -}}
{{- printf "%s/%s:%s" .Values.image.registry .Values.backend.image.repository (.Values.backend.image.tag | default .Chart.AppVersion) -}}
{{- end -}}

{{- define "pgdozor.frontendImage" -}}
{{- printf "%s/%s:%s" .Values.image.registry .Values.frontend.image.repository (.Values.frontend.image.tag | default .Chart.AppVersion) -}}
{{- end -}}

{{- define "pgdozor.secretName" -}}
{{- default (printf "%s-backend" (include "pgdozor.fullname" .)) .Values.secret.name -}}
{{- end -}}

{{- define "pgdozor.origin" -}}
{{- $scheme := ternary "https" "http" .Values.ingress.tls.enabled -}}
{{- $host := required "ingress.host is required" .Values.ingress.host -}}
{{- printf "%s://%s" $scheme $host -}}
{{- end -}}

{{- define "pgdozor.apiUrl" -}}
{{- printf "%s/api" (include "pgdozor.origin" .) -}}
{{- end -}}
