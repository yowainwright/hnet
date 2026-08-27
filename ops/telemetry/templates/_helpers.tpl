{{- define "hnet-telemetry.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "hnet-telemetry.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name (include "hnet-telemetry.name" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "hnet-telemetry.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "hnet-telemetry.labels" -}}
helm.sh/chart: {{ include "hnet-telemetry.chart" . }}
{{ include "hnet-telemetry.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "hnet-telemetry.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hnet-telemetry.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "hnet-telemetry.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- include "hnet-telemetry.fullname" . }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "hnet-telemetry.secretName" -}}
{{- default (include "hnet-telemetry.fullname" .) .Values.secret.existingName }}
{{- end }}

{{- define "hnet-telemetry.configmaps" -}}
{{- include (print $.Template.BasePath "/configmaps.yaml") . }}
{{- end }}
