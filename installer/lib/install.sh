#!/bin/bash

# Source common constants
source /installer/lib/common.sh

# Function to install Keycloak operator
install_keycloak_operator() {
  log_status "running" "deploying" "Installing Red Hat build of Keycloak Operator..."

  # Check if operator already installed
  if oc get "$OLM_SUBSCRIPTION_RESOURCE" "$KEYCLOAK_OPERATOR_NAME" -n "$TARGET_NAMESPACE" >/dev/null 2>&1; then
    local csv_name=$(oc get "$OLM_SUBSCRIPTION_RESOURCE" "$KEYCLOAK_OPERATOR_NAME" -n "$TARGET_NAMESPACE" -o jsonpath='{.status.installedCSV}' 2>/dev/null)
    if [[ -n "$csv_name" && "$csv_name" != "null" ]]; then
      local csv_phase=$(oc get "$OLM_CSV_RESOURCE" "$csv_name" -n "$TARGET_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)
      if [[ "$csv_phase" == "Succeeded" ]]; then
        log_status "running" "deploying" "Keycloak Operator already installed (CSV: $csv_name)"
        return 0
      fi
    fi
  fi

  # Check if an OperatorGroup already exists (avoid duplicates that cause OLM deadlock)
  local existing_og=$(oc get "$OLM_OPERATORGROUP_RESOURCE" -n "$TARGET_NAMESPACE" -o name 2>/dev/null | head -1)

  # Apply operator YAML with environment variable substitution
  export NAMESPACE="$TARGET_NAMESPACE"
  export CHANNEL="$KEYCLOAK_OPERATOR_CHANNEL"
  export STARTING_CSV="$KEYCLOAK_OPERATOR_MIN_VERSION"

  if [[ -n "$existing_og" ]]; then
    log_status "running" "deploying" "OperatorGroup exists ($existing_og), skipping creation..."
    # Strip OperatorGroup from YAML to avoid duplicate
    envsubst '${NAMESPACE} ${CHANNEL} ${STARTING_CSV}' < "$KEYCLOAK_OPERATOR_YAML" | python3 -c "
import sys
docs = sys.stdin.read().split('---')
for doc in docs:
    if 'kind: OperatorGroup' not in doc and doc.strip():
        print('---')
        print(doc, end='')
" | oc create --save-config -f - 2>&1 | grep -v "namespaces.*already exists" || true
  else
    envsubst '${NAMESPACE} ${CHANNEL} ${STARTING_CSV}' < "$KEYCLOAK_OPERATOR_YAML" | oc create --save-config -f - 2>&1 | grep -v "namespaces.*already exists" || true
  fi

  log_status "running" "deploying" "Waiting for Keycloak Operator to be ready..."

  # Wait for CSV to reach Succeeded phase (up to 10 minutes)
  local max_attempts=60
  local attempt=0

  while [[ $attempt -lt $max_attempts ]]; do
    local csv_name=$(oc get "$OLM_SUBSCRIPTION_RESOURCE" "$KEYCLOAK_OPERATOR_NAME" -n "$TARGET_NAMESPACE" -o jsonpath='{.status.installedCSV}' 2>/dev/null)

    if [[ -n "$csv_name" && "$csv_name" != "null" ]]; then
      local phase=$(oc get "$OLM_CSV_RESOURCE" "$csv_name" -n "$TARGET_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)

      if [[ "$phase" == "Succeeded" ]]; then
        log_status "running" "deploying" "Keycloak Operator ready (CSV: $csv_name)"
        break
      fi

      log_status "running" "deploying" "CSV phase: $phase (waiting... $attempt/60)"
    else
      log_status "running" "deploying" "Waiting for CSV to be created... ($attempt/60)"
    fi

    attempt=$((attempt + 1))
    sleep 10
  done

  if [[ $attempt -eq $max_attempts ]]; then
    log_error "Keycloak Operator did not reach Succeeded phase after 10 minutes"
  fi

  # Verify Keycloak CRDs exist
  log_status "running" "deploying" "Verifying Keycloak CRDs..."
  local crd_count=$(oc get crd -o name 2>/dev/null | grep -c "k8s.keycloak.org" || echo "0")

  if [[ "$crd_count" -eq 0 ]]; then
    log_error "Keycloak CRDs not found after operator installation"
  fi

  log_status "running" "deploying" "Keycloak Operator installation complete ($crd_count CRDs created)"
}

deploy_quickstart() {
  # Create target namespace if it doesn't exist
  log_status "running" "deploying" "Creating target namespace..."
  if ! oc get namespace "$TARGET_NAMESPACE" >/dev/null 2>&1; then
    oc create namespace "$TARGET_NAMESPACE" || log_error "Failed to create namespace $TARGET_NAMESPACE"
    log_status "running" "deploying" "Namespace created: $TARGET_NAMESPACE"
  else
    log_status "running" "deploying" "Namespace already exists: $TARGET_NAMESPACE"
  fi

  # Install Keycloak Operator (requires target namespace to exist)
  install_keycloak_operator

  # Validate required parameters
  if [[ -z "${PARAM_KEYCLOAK_REALM_TESTUSER_PASSWORD:-}" ]]; then
    log_error "Test user password is required. Set PARAM_KEYCLOAK_REALM_TESTUSER_PASSWORD environment variable."
  fi

  # Call the umbrella install script (which handles namespace creation and Helm installation)
  cd /installer/charts/peoplemesh-umbrella

  log_status "running" "deploying" "Running Peoplemesh installation script..."

  # Build arguments for install.sh
  INSTALL_ARGS=(
    --namespace "$TARGET_NAMESPACE"
    --test-password "$PARAM_KEYCLOAK_REALM_TESTUSER_PASSWORD"
  )

  # Optional: GPU acceleration
  if [[ "${PARAM_OLLAMA_GPU_ENABLED:-false}" == "true" ]]; then
    log_status "running" "deploying" "Enabling GPU for Ollama"
    INSTALL_ARGS+=(--ollama-gpu true)
  else
    INSTALL_ARGS+=(--ollama-gpu false)
  fi

  if [[ "${PARAM_DOCLING_GPU_ENABLED:-false}" == "true" ]]; then
    log_status "running" "deploying" "Enabling GPU for Docling"
    INSTALL_ARGS+=(--docling-gpu true)
  else
    INSTALL_ARGS+=(--docling-gpu false)
  fi

  # Optional: Organization customization (passed as --set arguments)
  if [[ -n "${PARAM_PEOPLEMESH_ORGANIZATION_NAME:-}" ]]; then
    INSTALL_ARGS+=(--set "peoplemesh.organization.name=$PARAM_PEOPLEMESH_ORGANIZATION_NAME")
  fi
  if [[ -n "${PARAM_PEOPLEMESH_ORGANIZATION_CONTACTEMAIL:-}" ]]; then
    INSTALL_ARGS+=(--set "peoplemesh.organization.contactEmail=$PARAM_PEOPLEMESH_ORGANIZATION_CONTACTEMAIL")
  fi

  # Run the install script
  log_status "running" "deploying" "Installing Helm chart (this may take 10-15 minutes)..."
  ./install.sh "${INSTALL_ARGS[@]}" || log_error "Installation failed. Check logs above for details."

  log_status "running" "deploying" "Installation complete"
}
