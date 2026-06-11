{{/*
Expand the name of the chart.
*/}}
{{- define "peoplemesh-umbrella.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "peoplemesh-umbrella.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "peoplemesh-umbrella.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "peoplemesh-umbrella.labels" -}}
helm.sh/chart: {{ include "peoplemesh-umbrella.chart" . }}
{{ include "peoplemesh-umbrella.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "peoplemesh-umbrella.selectorLabels" -}}
app.kubernetes.io/name: {{ include "peoplemesh-umbrella.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Generate Keycloak client secret
*/}}
{{- define "peoplemesh-umbrella.keycloakClientSecret" -}}
{{- if .Values.keycloak.realm.client.clientSecret }}
{{- .Values.keycloak.realm.client.clientSecret }}
{{- else }}
{{- randAlphaNum 32 }}
{{- end }}
{{- end }}

{{/*
Get cluster domain from OpenShift console route
*/}}
{{- define "peoplemesh-umbrella.clusterDomain" -}}
{{- $console := lookup "route.openshift.io/v1" "Route" "openshift-console" "console" }}
{{- if $console }}
{{- $host := $console.spec.host }}
{{- regexReplaceAll "^console-openshift-console\\." $host "" }}
{{- else }}
apps.cluster.local
{{- end }}
{{- end }}

{{/*
Construct Keycloak issuer URL
*/}}
{{- define "peoplemesh-umbrella.keycloakIssuerUrl" -}}
{{- $clusterDomain := include "peoplemesh-umbrella.clusterDomain" . }}
{{- printf "https://keycloak-%s.%s/realms/%s" .Release.Namespace $clusterDomain .Values.keycloak.realm.name }}
{{- end }}

{{/*
Construct Peoplemesh redirect URI
*/}}
{{- define "peoplemesh-umbrella.peoplemeshRedirectUri" -}}
{{- $clusterDomain := include "peoplemesh-umbrella.clusterDomain" . }}
{{- printf "https://peoplemesh-%s.%s/api/v1/auth/callback/keycloak" .Release.Namespace $clusterDomain }}
{{- end }}

{{/*
Construct Peoplemesh web origin
*/}}
{{- define "peoplemesh-umbrella.peoplemeshWebOrigin" -}}
{{- $clusterDomain := include "peoplemesh-umbrella.clusterDomain" . }}
{{- printf "https://peoplemesh-%s.%s" .Release.Namespace $clusterDomain }}
{{- end }}
