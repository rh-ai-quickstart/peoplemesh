{{/*
Get the target namespace - use release namespace if values.namespace is empty
*/}}
{{- define "keycloak.namespace" -}}
{{- if .Values.namespace }}
{{- .Values.namespace }}
{{- else }}
{{- .Release.Namespace }}
{{- end }}
{{- end }}

{{/*
Get the Keycloak client secret - REQUIRED, no defaults
*/}}
{{- define "keycloak.clientSecret" -}}
{{- required "keycloak.realm.client.clientSecret is required" .Values.realm.client.clientSecret }}
{{- end }}

{{/*
Get cluster domain from OpenShift console route
*/}}
{{- define "keycloak.clusterDomain" -}}
{{- $console := lookup "route.openshift.io/v1" "Route" "openshift-console" "console" }}
{{- if $console }}
{{- $host := $console.spec.host }}
{{- regexReplaceAll "^console-openshift-console\\." $host "" }}
{{- else }}
apps.cluster.local
{{- end }}
{{- end }}

{{/*
Construct Peoplemesh redirect URI with actual cluster domain
*/}}
{{- define "keycloak.peoplemeshRedirectUri" -}}
{{- $clusterDomain := include "keycloak.clusterDomain" . }}
{{- printf "https://peoplemesh-%s.%s/api/v1/auth/callback/keycloak" .Release.Namespace $clusterDomain }}
{{- end }}

{{/*
Construct Peoplemesh web origin with actual cluster domain
*/}}
{{- define "keycloak.peoplemeshWebOrigin" -}}
{{- $clusterDomain := include "keycloak.clusterDomain" . }}
{{- printf "https://peoplemesh-%s.%s" .Release.Namespace $clusterDomain }}
{{- end }}

{{/*
Get PostgreSQL password - REQUIRED, no defaults
*/}}
{{- define "keycloak.postgresPassword" -}}
{{- required "keycloak.postgres.password is required" .Values.postgres.password }}
{{- end }}

{{/*
Construct Keycloak issuer URL with actual cluster domain
*/}}
{{- define "keycloak.issuerUrl" -}}
{{- $clusterDomain := include "keycloak.clusterDomain" . }}
{{- $namespace := include "keycloak.namespace" . }}
{{- printf "https://%s-%s.%s/realms/%s" .Values.applicationName $namespace $clusterDomain .Values.realm.name }}
{{- end }}
