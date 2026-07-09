{{/*
Get session secret - REQUIRED from user
*/}}
{{- define "peoplemesh.sessionSecret" -}}
{{- $secret := lookup "v1" "Secret" .Release.Namespace "peoplemesh-secrets" -}}
{{- if $secret -}}
  {{- index $secret.data "SESSION_SECRET" | b64dec -}}
{{- else -}}
  {{- required "peoplemesh.security.sessionSecret is required. Generate with: openssl rand -base64 24" .Values.security.sessionSecret -}}
{{- end -}}
{{- end }}

{{/*
Get OAuth state secret - REQUIRED from user
*/}}
{{- define "peoplemesh.oauthStateSecret" -}}
{{- $secret := lookup "v1" "Secret" .Release.Namespace "peoplemesh-secrets" -}}
{{- if $secret -}}
  {{- index $secret.data "OAUTH_STATE_SECRET" | b64dec -}}
{{- else -}}
  {{- required "peoplemesh.security.oauthStateSecret is required. Generate with: openssl rand -base64 24" .Values.security.oauthStateSecret -}}
{{- end -}}
{{- end }}

{{/*
Get maintenance API key - REQUIRED from user
*/}}
{{- define "peoplemesh.maintenanceApiKey" -}}
{{- $secret := lookup "v1" "Secret" .Release.Namespace "peoplemesh-secrets" -}}
{{- if $secret -}}
  {{- index $secret.data "MAINTENANCE_API_KEY" | b64dec -}}
{{- else -}}
  {{- required "peoplemesh.security.maintenanceApiKey is required. Generate with: openssl rand -base64 24" .Values.security.maintenanceApiKey -}}
{{- end -}}
{{- end }}

{{/*
Get Keycloak issuer URL - auto-detect from cluster if not provided
*/}}
{{- define "peoplemesh.keycloakIssuerUrl" -}}
{{- if .Values.security.oidc.keycloak.issuerUrl -}}
  {{- .Values.security.oidc.keycloak.issuerUrl -}}
{{- else -}}
  {{- $console := lookup "route.openshift.io/v1" "Route" "openshift-console" "console" }}
  {{- if $console }}
    {{- $host := $console.spec.host }}
    {{- $clusterDomain := regexReplaceAll "^console-openshift-console\\." $host "" }}
    {{- printf "https://keycloak-%s.%s/realms/peoplemesh" .Release.Namespace $clusterDomain }}
  {{- else }}
    {{- printf "https://keycloak-%s.apps.cluster.local/realms/peoplemesh" .Release.Namespace }}
  {{- end }}
{{- end -}}
{{- end }}
