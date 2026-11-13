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

{{- define "hnet-telemetry.clients" -}}
{{- $clients := .Values.clients -}}
{{- if eq $clients nil -}}
{{- $clients = list
  (dict "name" "mac-studio" "port" .Values.gateway.service.port "tokenEnv" "HNET_CLIENT_TOKEN_4318" "tokenKey" .Values.secret.keys.macStudioToken)
  (dict "name" "mac-mini-1" "port" .Values.gateway.service.macMini1Port "tokenEnv" "HNET_CLIENT_TOKEN_4319" "tokenKey" .Values.secret.keys.macMini1Token)
  (dict "name" "mac-mini-2" "port" .Values.gateway.service.macMini2Port "tokenEnv" "HNET_CLIENT_TOKEN_4320" "tokenKey" .Values.secret.keys.macMini2Token) -}}
{{- end -}}
{{- if eq (len $clients) 0 -}}{{- fail "Configure at least one client" -}}{{- end -}}
{{- $names := dict -}}{{- $ports := dict -}}{{- $result := list -}}
{{- $envNames := dict -}}{{- $tokenKeys := dict -}}
{{- range $client := $clients -}}
{{- $port := int $client.port -}}
{{- $key := printf "%d" $port -}}
{{- if ne (toString $client.port) $key -}}{{- fail "Client receiver ports must be integers" -}}{{- end -}}
{{- if or (not (regexMatch "^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$" $client.name)) (lt $port 1024) (gt $port 65535) (eq $port 13133) -}}
{{- fail "Invalid client name or receiver port" -}}
{{- end -}}
{{- if or (hasKey $names (lower $client.name)) (hasKey $ports $key) -}}{{- fail "Client names and ports must be unique" -}}{{- end -}}
{{- $_ := set $names (lower $client.name) true -}}{{- $_ := set $ports $key true -}}
{{- $env := default (printf "HNET_CLIENT_TOKEN_%d" $port) $client.tokenEnv -}}
{{- $secret := default $env $client.tokenKey -}}
{{- if or (not (regexMatch "^[A-Z_][A-Z0-9_]*$" $env)) (not (regexMatch "^[A-Za-z0-9._-]+$" $secret)) -}}
{{- fail "Invalid client token environment name or Secret key" -}}
{{- end -}}
{{- if or (hasKey $envNames $env) (hasKey $tokenKeys $secret) -}}{{- fail "Each client must have a separate credential binding" -}}{{- end -}}
{{- $_ := set $envNames $env true -}}{{- $_ := set $tokenKeys $secret true -}}
{{- $result = append $result (dict "name" $client.name "port" $port "tokenEnv" $env "tokenKey" $secret) -}}
{{- end -}}
{{- toJson $result -}}
{{- end }}

{{- define "hnet-telemetry.clientConfig" -}}
{{- $extensions := dict -}}{{- $receivers := dict -}}{{- $processors := dict -}}{{- $pipelines := dict -}}
{{- $enabled := list "file_storage" "health_check" -}}
{{- range $client := (include "hnet-telemetry.clients" . | fromJsonArray) -}}
{{- $id := printf "client_%d" (int $client.port) -}}
{{- $auth := printf "bearertokenauth/%s" $id -}}{{- $receiver := printf "otlp/%s" $id -}}{{- $host := printf "resource/%s" $id -}}
{{- $_ := set $extensions $auth (dict "tokens" (list (printf "${env:%s}" $client.tokenEnv))) -}}
{{- $_ := set $receivers $receiver (dict "protocols" (dict "http" (dict "endpoint" (printf "0.0.0.0:%d" (int $client.port)) "auth" (dict "authenticator" $auth)))) -}}
{{- $_ := set $processors $host (dict "attributes" (list (dict "key" "host.name" "action" "upsert" "value" $client.name))) -}}
{{- $enabled = append $enabled $auth -}}
{{- range $signal := list "logs" "metrics" "traces" -}}
{{- $_ := set $pipelines (printf "%s/%s" $signal $id) (dict "receivers" (list $receiver) "processors" (list "memory_limiter" "transform/privacy" "redaction/sensitive" $host "resource/pipeline") "exporters" (list "clickhouse")) -}}
{{- end -}}
{{- end -}}
{{- toJson (dict "extensions" $extensions "receivers" $receivers "processors" $processors "service" (dict "extensions" $enabled "pipelines" $pipelines)) -}}
{{- end }}
