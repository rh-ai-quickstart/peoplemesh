{{/*
Get PostgreSQL password - REQUIRED, no defaults
*/}}
{{- define "pgvector.postgresPassword" -}}
{{- required "pgvector.postgres.password is required" .Values.postgres.password }}
{{- end }}
