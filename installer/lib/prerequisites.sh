#!/bin/bash

check_prerequisites() {
  local missing=()

  # Check OpenShift version
  log_status "running" "validating" "Checking OpenShift version..."
  if ! OCP_VERSION=$(oc version -o json 2>/dev/null | jq -r '.openshiftVersion' 2>/dev/null | cut -d. -f1,2); then
    missing+=("Unable to determine OpenShift version (is oc authenticated?)")
  else
    MIN_VERSION="4.12"
    if [[ "$(printf '%s\n' "$MIN_VERSION" "$OCP_VERSION" | sort -V | head -n1)" != "$MIN_VERSION" ]]; then
      missing+=("OpenShift $MIN_VERSION+ required (found $OCP_VERSION)")
    fi
  fi

  # Check for Keycloak Operator
  log_status "running" "validating" "Checking for Red Hat build of Keycloak Operator..."
  if ! oc get csv -n "$TARGET_NAMESPACE" 2>/dev/null | grep -q 'rhbk-operator'; then
    missing+=("Red Hat build of Keycloak Operator must be installed in namespace '$TARGET_NAMESPACE'. Install from OperatorHub before deploying.")
  fi

  # Check for required CRDs
  log_status "running" "validating" "Checking for required CRDs..."
  if ! oc get crd keycloaks.k8s.keycloak.org >/dev/null 2>&1; then
    missing+=("CRD keycloaks.k8s.keycloak.org not found (install Keycloak Operator)")
  fi
  if ! oc get crd keycloakrealmimports.k8s.keycloak.org >/dev/null 2>&1; then
    missing+=("CRD keycloakrealmimports.k8s.keycloak.org not found (install Keycloak Operator)")
  fi

  # Check for storage class with ReadWriteOnce
  log_status "running" "validating" "Checking for ReadWriteOnce storage class..."
  if ! oc get sc 2>/dev/null | awk 'NR>1 {print $0}' | grep -q 'ReadWriteOnce\|RWO'; then
    # Fallback: check if any storage class exists (many don't show mode in name)
    if ! oc get sc --no-headers 2>/dev/null | grep -q .; then
      missing+=("No storage classes found. At least one ReadWriteOnce storage class is required.")
    fi
  fi

  # Check GPU availability if GPU is requested
  if [[ "${PARAM_OLLAMA_GPU_ENABLED:-false}" == "true" || "${PARAM_DOCLING_GPU_ENABLED:-false}" == "true" ]]; then
    log_status "running" "validating" "Checking for GPU resources..."
    GPU_COUNT=$(oc get nodes -o json 2>/dev/null | jq '[.items[].status.capacity."nvidia.com/gpu" // "0" | tonumber] | add' 2>/dev/null || echo "0")
    if [[ "$GPU_COUNT" -eq 0 ]]; then
      missing+=("GPU acceleration requested but no NVIDIA GPUs found in cluster. Either disable GPU settings or install NVIDIA GPU Operator and add GPU nodes.")
    fi
  fi

  # Check for sufficient cluster resources
  log_status "running" "validating" "Checking cluster capacity..."
  TOTAL_CPU=$(oc get nodes -o json 2>/dev/null | jq '[.items[].status.capacity.cpu | rtrimstr("m") | tonumber] | add' 2>/dev/null || echo "0")
  TOTAL_MEM_KI=$(oc get nodes -o json 2>/dev/null | jq '[.items[].status.capacity.memory | rtrimstr("Ki") | tonumber] | add' 2>/dev/null || echo "0")
  TOTAL_MEM_GB=$(echo "scale=2; $TOTAL_MEM_KI / 1024 / 1024" | bc)

  MIN_CPU=4
  MIN_MEM_GB=16
  if [[ "$TOTAL_CPU" -lt "$MIN_CPU" ]]; then
    missing+=("Insufficient CPU: need ${MIN_CPU} cores, cluster has ${TOTAL_CPU} cores")
  fi
  if (( $(echo "$TOTAL_MEM_GB < $MIN_MEM_GB" | bc -l) )); then
    missing+=("Insufficient memory: need ${MIN_MEM_GB}GB RAM, cluster has ${TOTAL_MEM_GB}GB")
  fi

  # Report results
  if [[ ${#missing[@]} -gt 0 ]]; then
    MISSING_JSON=$(printf '%s\n' "${missing[@]}" | jq -R . | jq -s .)
    log_prerequisites_failed "$MISSING_JSON"
    return 1
  fi

  log_status "running" "validating" "All prerequisites satisfied"
  return 0
}
