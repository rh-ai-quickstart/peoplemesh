#!/bin/bash

deploy_quickstart() {
  # Helper function to generate secrets if not provided
  generate_secret() {
    local param_name=$1
    local env_var="PARAM_${param_name^^}"
    # Replace dots and dashes with underscores for env var naming
    env_var=${env_var//\./_}
    env_var=${env_var//-/_}

    if [[ -z "${!env_var:-}" ]]; then
      openssl rand -base64 24
    else
      echo "${!env_var}"
    fi
  }

  # Generate or use provided secrets
  KC_DB_PASSWORD=$(generate_secret "keycloak_postgres_password")
  PG_DB_PASSWORD=$(generate_secret "pgvector_postgres_password")
  CLIENT_SECRET=$(generate_secret "keycloak_realm_client_clientsecret")
  SESSION_SECRET=$(generate_secret "peoplemesh_security_sessionsecret")
  OAUTH_SECRET=$(generate_secret "peoplemesh_security_oauthstatesecret")
  MAINT_KEY=$(generate_secret "peoplemesh_security_maintenanceapikey")
  TEST_USER_PASSWORD="${PARAM_KEYCLOAK_REALM_TESTUSER_PASSWORD:-SecurePassword1}"

  log_status "running" "deploying" "Building Helm dependency updates..."
  cd /installer/charts/peoplemesh-umbrella
  helm dependency update || log_error "Helm dependency update failed"

  # Build Helm command
  HELM_ARGS=(
    install peoplemesh .
    --namespace "$TARGET_NAMESPACE"
    --create-namespace
    --timeout 15m
    --wait
    --set "keycloak.postgres.password=$KC_DB_PASSWORD"
    --set "pgvector.postgres.password=$PG_DB_PASSWORD"
    --set "keycloak.realm.client.clientSecret=$CLIENT_SECRET"
    --set "peoplemesh.security.sessionSecret=$SESSION_SECRET"
    --set "peoplemesh.security.oauthStateSecret=$OAUTH_SECRET"
    --set "peoplemesh.security.maintenanceApiKey=$MAINT_KEY"
    --set "keycloak.realm.testUser.password=$TEST_USER_PASSWORD"
  )

  # Handle INSTALL_MODE (demo vs production)
  if [[ "$INSTALL_MODE" == "demo" ]]; then
    log_status "running" "deploying" "Demo mode: including sample data"
    HELM_ARGS+=(--set "peoplemesh.seedData.enabled=true")
  else
    log_status "running" "deploying" "Production mode: clean database"
    HELM_ARGS+=(--set "peoplemesh.seedData.enabled=false")
  fi

  # Add GPU flags if enabled
  if [[ "${PARAM_OLLAMA_GPU_ENABLED:-false}" == "true" ]]; then
    log_status "running" "deploying" "Enabling GPU for Ollama"
    HELM_ARGS+=(--set "ollama.gpu.enabled=true")
  fi
  if [[ "${PARAM_DOCLING_GPU_ENABLED:-false}" == "true" ]]; then
    log_status "running" "deploying" "Enabling GPU for Docling"
    HELM_ARGS+=(--set "docling.gpu.enabled=true")
  fi

  # Add LLM mode configuration
  LLM_MODE="${PARAM_PEOPLEMESH_LLM_MODE:-local}"
  LLM_MODE=${LLM_MODE,,}  # Convert to lowercase

  if [[ "$LLM_MODE" == "external" ]]; then
    log_status "running" "deploying" "Configuring external LLM mode"
    HELM_ARGS+=(
      --set "peoplemesh.llm.mode=external"
      --set "ollama.enabled=false"
    )
    if [[ -n "${PARAM_PEOPLEMESH_LLM_EXTERNAL_APIKEY:-}" ]]; then
      HELM_ARGS+=(--set "peoplemesh.llm.external.apiKey=$PARAM_PEOPLEMESH_LLM_EXTERNAL_APIKEY")
    fi
    if [[ -n "${PARAM_PEOPLEMESH_LLM_EXTERNAL_BASEURL:-}" ]]; then
      HELM_ARGS+=(--set "peoplemesh.llm.external.baseUrl=$PARAM_PEOPLEMESH_LLM_EXTERNAL_BASEURL")
    fi
    if [[ -n "${PARAM_PEOPLEMESH_LLM_EXTERNAL_CHATMODEL:-}" ]]; then
      HELM_ARGS+=(--set "peoplemesh.llm.external.chatModel=$PARAM_PEOPLEMESH_LLM_EXTERNAL_CHATMODEL")
    fi
  fi

  # Add organization branding
  if [[ -n "${PARAM_PEOPLEMESH_ORGANIZATION_NAME:-}" ]]; then
    HELM_ARGS+=(--set "peoplemesh.organization.name=$PARAM_PEOPLEMESH_ORGANIZATION_NAME")
  fi
  if [[ -n "${PARAM_PEOPLEMESH_ORGANIZATION_CONTACTEMAIL:-}" ]]; then
    HELM_ARGS+=(--set "peoplemesh.organization.contactEmail=$PARAM_PEOPLEMESH_ORGANIZATION_CONTACTEMAIL")
  fi

  # Add OAuth providers
  if [[ -n "${PARAM_PEOPLEMESH_OIDC_GOOGLE_CLIENTID:-}" ]]; then
    log_status "running" "deploying" "Configuring Google OAuth"
    HELM_ARGS+=(--set "peoplemesh.oidc.google.clientId=$PARAM_PEOPLEMESH_OIDC_GOOGLE_CLIENTID")
  fi
  if [[ -n "${PARAM_PEOPLEMESH_OIDC_GOOGLE_CLIENTSECRET:-}" ]]; then
    HELM_ARGS+=(--set "peoplemesh.oidc.google.clientSecret=$PARAM_PEOPLEMESH_OIDC_GOOGLE_CLIENTSECRET")
  fi
  if [[ -n "${PARAM_PEOPLEMESH_OIDC_MICROSOFT_CLIENTID:-}" ]]; then
    log_status "running" "deploying" "Configuring Microsoft OAuth"
    HELM_ARGS+=(--set "peoplemesh.oidc.microsoft.clientId=$PARAM_PEOPLEMESH_OIDC_MICROSOFT_CLIENTID")
  fi
  if [[ -n "${PARAM_PEOPLEMESH_OIDC_MICROSOFT_CLIENTSECRET:-}" ]]; then
    HELM_ARGS+=(--set "peoplemesh.oidc.microsoft.clientSecret=$PARAM_PEOPLEMESH_OIDC_MICROSOFT_CLIENTSECRET")
  fi

  # Run Helm install
  log_status "running" "deploying" "Installing Helm chart (this may take 10-15 minutes)..."
  helm "${HELM_ARGS[@]}" || log_error "Helm installation failed. Check logs above for details."

  log_status "running" "deploying" "Helm installation complete"
}
