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

{{- define "pgdozor.databaseSecretName" -}}
{{- if .Values.backend.existingSecret -}}
{{- .Values.backend.existingSecret -}}
{{- else -}}
{{- printf "%s-backend" (include "pgdozor.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "pgdozor.databaseSecretKey" -}}
{{- if .Values.backend.existingSecret -}}
{{- .Values.backend.existingSecretKey -}}
{{- else -}}
DATABASE_URL
{{- end -}}
{{- end -}}

{{- define "pgdozor.scheme" -}}
{{- if .Values.ingress.tls.enabled -}}https{{- else -}}http{{- end -}}
{{- end -}}

{{- define "pgdozor.appOrigin" -}}
{{- printf "%s://%s" (include "pgdozor.scheme" .) .Values.ingress.host -}}
{{- end -}}

{{- define "pgdozor.apiOrigin" -}}
{{- if .Values.ingress.dualHost.enabled -}}
{{- printf "%s://%s" (include "pgdozor.scheme" .) .Values.ingress.dualHost.apiHost -}}
{{- else -}}
{{- include "pgdozor.appOrigin" . -}}
{{- end -}}
{{- end -}}

{{- define "pgdozor.publicApiUrl" -}}
{{- if .Values.frontend.publicApiUrl -}}
{{- .Values.frontend.publicApiUrl -}}
{{- else -}}
{{- include "pgdozor.apiOrigin" . -}}
{{- end -}}
{{- end -}}

{{- define "pgdozor.corsOrigins" -}}
{{- if .Values.backend.corsAllowedOrigins -}}
{{- .Values.backend.corsAllowedOrigins -}}
{{- else -}}
{{- include "pgdozor.appOrigin" . -}}
{{- end -}}
{{- end -}}
