{{/*
Get PostgreSQL password - REQUIRED from user
*/}}
{{- define "pgvector.postgresPassword" -}}
{{- $secret := lookup "v1" "Secret" .Release.Namespace "pgvector-database" -}}
{{- if $secret -}}
  {{- index $secret.data "DATABASE_PASSWORD" | b64dec -}}
{{- else -}}
  {{- required "pgvector.postgres.password is required. Generate with: openssl rand -base64 24" .Values.postgres.password -}}
{{- end -}}
{{- end }}
