#!/bin/bash

# Source common constants
source /installer/lib/common.sh

# Auto-detect the NoSchedule taint keys on GPU-capable nodes and emit a JSON
# tolerations array. GPU-requiring pods (Ollama, Docling, vLLM) need a matching
# toleration to schedule onto tainted GPU nodes; different cluster/instance types
# use different keys (e.g. g5-gpu, g6e-gpu), so we discover them at deploy time
# rather than hardcoding. Falls back to the standard nvidia.com/gpu key when no
# tainted GPU nodes are found.
detect_gpu_tolerations() {
  local taint_keys
  taint_keys=$(oc get nodes -o json 2>/dev/null | \
    jq -r '[.items[] | select(.status.allocatable["nvidia.com/gpu"] // "0" | tonumber > 0) | .spec.taints // [] | .[] | select(.effect == "NoSchedule") | .key] | unique | .[]' 2>/dev/null || echo "")

  if [[ -z "$taint_keys" ]]; then
    echo '[{"effect":"NoSchedule","key":"nvidia.com/gpu","operator":"Exists"}]'
    return
  fi

  local json="[" first=true key
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    if [[ "$first" == "true" ]]; then first=false; else json+=","; fi
    json+="{\"effect\":\"NoSchedule\",\"key\":\"${key}\",\"operator\":\"Exists\"}"
  done <<< "$taint_keys"
  json+="]"
  echo "$json"
}

# Build the GPU tolerations JSON. If the operator/user supplied taint keys via
# the gpu.tolerationKeys parameter (PARAM_GPU_TOLERATIONKEYS, a comma-separated
# list), those completely replace auto-detection; otherwise auto-detect from the
# cluster's GPU nodes.
build_gpu_tolerations() {
  local keys="${PARAM_GPU_TOLERATIONKEYS:-}"
  if [[ -z "$keys" ]]; then
    detect_gpu_tolerations
    return
  fi

  local json="[" first=true key
  local IFS=','
  for key in $keys; do
    key="$(echo "$key" | xargs)"   # trim surrounding whitespace
    [[ -z "$key" ]] && continue
    if [[ "$first" == "true" ]]; then first=false; else json+=","; fi
    json+="{\"effect\":\"NoSchedule\",\"key\":\"${key}\",\"operator\":\"Exists\"}"
  done
  json+="]"
  echo "$json"
}

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
  # Defense-in-depth namespace collision guard. check_prerequisites already
  # blocks INSTALL when the target namespace exists, but re-check here in case
  # deploy_quickstart is ever invoked directly, or the namespace was created
  # between the prerequisite check and now (TOCTOU). Never proceed into a
  # pre-existing namespace -- that would risk clobbering resources we don't own.
  log_status "running" "deploying" "Checking target namespace: $TARGET_NAMESPACE"
  if oc get namespace "$TARGET_NAMESPACE" >/dev/null 2>&1; then
    log_error "Target namespace '$TARGET_NAMESPACE' already exists. Installation aborted to avoid clobbering existing resources. Delete it (oc delete namespace $TARGET_NAMESPACE) or run uninstall_delete_all, or choose a namespace that does not yet exist, then retry."
  fi

  log_status "running" "deploying" "Creating target namespace..."
  oc create namespace "$TARGET_NAMESPACE" || log_error "Failed to create namespace $TARGET_NAMESPACE"
  log_status "running" "deploying" "Namespace created: $TARGET_NAMESPACE"

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

  # Optional: Organization customization. These are free-text values (an org
  # name like "Red Hat, Inc." may contain spaces and commas), so pass them with
  # --set-string and backslash-escape literal commas that Helm would otherwise
  # treat as --set multi-value delimiters.
  if [[ -n "${PARAM_PEOPLEMESH_ORGANIZATION_NAME:-}" ]]; then
    org_name="${PARAM_PEOPLEMESH_ORGANIZATION_NAME//,/\\,}"
    INSTALL_ARGS+=(--set-string "peoplemesh.organization.name=$org_name")
  fi
  if [[ -n "${PARAM_PEOPLEMESH_ORGANIZATION_CONTACTEMAIL:-}" ]]; then
    org_email="${PARAM_PEOPLEMESH_ORGANIZATION_CONTACTEMAIL//,/\\,}"
    INSTALL_ARGS+=(--set-string "peoplemesh.organization.contactEmail=$org_email")
  fi

  # GPU node tolerations. Applied to every GPU-requiring pod (Ollama, Docling,
  # vLLM) via the chart's global.gpuTolerations so they can schedule onto tainted
  # GPU nodes. Honor an explicit override (gpu.tolerationKeys) if provided,
  # otherwise auto-detect the cluster's GPU node taint keys. Passed through the
  # umbrella install.sh via its --set pass-through.
  local gpu_tolerations
  if [[ -n "${PARAM_GPU_TOLERATIONKEYS:-}" ]]; then
    log_status "running" "deploying" "Using provided GPU taint keys: ${PARAM_GPU_TOLERATIONKEYS}"
  else
    log_status "running" "deploying" "Auto-detecting GPU node taint keys..."
  fi
  gpu_tolerations="$(build_gpu_tolerations)"
  log_status "running" "deploying" "GPU tolerations: ${gpu_tolerations}"

  local gpu_idx=0 row t_key t_effect t_operator
  for row in $(echo "$gpu_tolerations" | jq -c '.[]'); do
    t_key=$(echo "$row" | jq -r '.key')
    t_effect=$(echo "$row" | jq -r '.effect')
    t_operator=$(echo "$row" | jq -r '.operator')
    INSTALL_ARGS+=(--set "global.gpuTolerations[${gpu_idx}].key=${t_key}")
    INSTALL_ARGS+=(--set "global.gpuTolerations[${gpu_idx}].effect=${t_effect}")
    INSTALL_ARGS+=(--set "global.gpuTolerations[${gpu_idx}].operator=${t_operator}")
    gpu_idx=$((gpu_idx + 1))
  done

  # Run the install script
  log_status "running" "deploying" "Installing Helm chart (this may take 10-15 minutes)..."
  ./install.sh "${INSTALL_ARGS[@]}" || log_error "Installation failed. Check logs above for details."

  log_status "running" "deploying" "Installation complete"
}
