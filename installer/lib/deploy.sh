#!/bin/bash

deploy_quickstart() {
  log_status "running" "deploying" "Building Helm dependency updates..."
  cd /installer/charts/peoplemesh-umbrella
  helm dependency update || log_error "Helm dependency update failed"

  # Check for openssl (required by install.sh)
  if ! command -v openssl >/dev/null 2>&1; then
    log_error "openssl command not found. Required for secret generation."
  fi

  # Validate required parameters
  if [[ -z "${PARAM_KEYCLOAK_REALM_TESTUSER_PASSWORD:-}" ]]; then
    log_error "Test user password is required. Set PARAM_KEYCLOAK_REALM_TESTUSER_PASSWORD environment variable."
  fi

  # Generate secure secrets automatically (not exposed to user)
  log_status "running" "deploying" "Generating secure secrets..."
  KC_DB_PASSWORD=$(openssl rand -base64 24)
  PG_DB_PASSWORD=$(openssl rand -base64 24)
  CLIENT_SECRET=$(openssl rand -base64 24)
  SESSION_SECRET=$(openssl rand -base64 24)
  OAUTH_SECRET=$(openssl rand -base64 24)
  MAINT_KEY=$(openssl rand -base64 24)

  # Build Helm command with auto-generated secrets
  HELM_ARGS=(
    install peoplemesh .
    --namespace "$TARGET_NAMESPACE"
    --timeout 15m
    --wait
    --set "keycloak.postgres.password=$KC_DB_PASSWORD"
    --set "pgvector.postgres.password=$PG_DB_PASSWORD"
    --set "keycloak.realm.client.clientSecret=$CLIENT_SECRET"
    --set "peoplemesh.security.sessionSecret=$SESSION_SECRET"
    --set "peoplemesh.security.oauthStateSecret=$OAUTH_SECRET"
    --set "peoplemesh.security.maintenanceApiKey=$MAINT_KEY"
    --set "keycloak.realm.testUser.password=$PARAM_KEYCLOAK_REALM_TESTUSER_PASSWORD"
  )

  # Optional: GPU acceleration
  if [[ "${PARAM_OLLAMA_GPU_ENABLED:-false}" == "true" ]]; then
    log_status "running" "deploying" "Enabling GPU for Ollama"
    HELM_ARGS+=(--set "ollama.gpu.enabled=true")
  fi
  if [[ "${PARAM_DOCLING_GPU_ENABLED:-false}" == "true" ]]; then
    log_status "running" "deploying" "Enabling GPU for Docling"
    HELM_ARGS+=(--set "docling.gpu.enabled=true")
  fi

  # Optional: Organization customization
  if [[ -n "${PARAM_PEOPLEMESH_ORGANIZATION_NAME:-}" ]]; then
    HELM_ARGS+=(--set "peoplemesh.organization.name=$PARAM_PEOPLEMESH_ORGANIZATION_NAME")
  fi
  if [[ -n "${PARAM_PEOPLEMESH_ORGANIZATION_CONTACTEMAIL:-}" ]]; then
    HELM_ARGS+=(--set "peoplemesh.organization.contactEmail=$PARAM_PEOPLEMESH_ORGANIZATION_CONTACTEMAIL")
  fi

  # Run Helm install
  log_status "running" "deploying" "Installing Helm chart (this may take 10-15 minutes)..."
  helm "${HELM_ARGS[@]}" || log_error "Helm installation failed. Check logs above for details."

  # Clear sensitive variables from memory
  KC_DB_PASSWORD=""
  PG_DB_PASSWORD=""
  CLIENT_SECRET=""
  SESSION_SECRET=""
  OAUTH_SECRET=""
  MAINT_KEY=""

  log_status "running" "deploying" "Helm installation complete"
}
