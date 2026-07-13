#!/bin/bash

check_prerequisites() {
  local missing=()

  # Check if target namespace exists (report status, don't create)
  log_status "running" "validating" "Checking target namespace: $TARGET_NAMESPACE"
  if oc get namespace "$TARGET_NAMESPACE" >/dev/null 2>&1; then
    log_status "running" "validating" "Target namespace exists"
  else
    log_status "running" "validating" "Target namespace does not exist (will be created during installation)"
  fi

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

  # Check for Keycloak Operator availability in catalog
  log_status "running" "validating" "Checking for Red Hat build of Keycloak Operator in catalog..."

  # Check if rhbk-operator package is available in redhat-operators catalog
  RHBK_AVAILABLE=$(oc get packagemanifests -n openshift-marketplace rhbk-operator -o json 2>/dev/null | \
    jq -r '.status.catalogSource' 2>/dev/null)

  if [[ "$RHBK_AVAILABLE" != "redhat-operators" ]]; then
    missing+=("Red Hat build of Keycloak Operator (rhbk-operator) not found in redhat-operators catalog. Ensure OperatorHub is configured.")
  else
    # Check if the required version (26.6.4 or greater) is available
    # Version format: rhbk-operator.v26.6.4-opr.1
    AVAILABLE_CSV=$(oc get packagemanifests -n openshift-marketplace rhbk-operator -o json 2>/dev/null | \
      jq -r '.status.channels[] | select(.name == "stable-v26") | .currentCSV' 2>/dev/null)

    if [[ -z "$AVAILABLE_CSV" || "$AVAILABLE_CSV" == "null" ]]; then
      missing+=("Red Hat build of Keycloak Operator channel 'stable-v26' not found. Required version: 26.6.4 or greater.")
    else
      # Extract version number (e.g., "rhbk-operator.v26.6.4-opr.1" -> "26.6.4")
      AVAILABLE_VERSION=$(echo "$AVAILABLE_CSV" | sed 's/rhbk-operator\.v//' | sed 's/-opr\..*//')
      MIN_VERSION="26.6.4"

      # Compare versions using sort -V (version sort)
      if [[ "$(printf '%s\n' "$MIN_VERSION" "$AVAILABLE_VERSION" | sort -V | head -n1)" != "$MIN_VERSION" ]]; then
        missing+=("Red Hat build of Keycloak Operator version $AVAILABLE_VERSION found, but version $MIN_VERSION or greater is required.")
      else
        log_status "running" "validating" "Found rhbk-operator in catalog: $AVAILABLE_CSV (version $AVAILABLE_VERSION >= $MIN_VERSION)"
      fi
    fi
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
    GPU_COUNT=$(oc get nodes -o json 2>/dev/null | jq '
      [.items[].status.capacity."nvidia.com/gpu" // "0"] |
      map(tonumber) |
      add // 0' 2>/dev/null)
    GPU_COUNT=${GPU_COUNT:-0}

    if [[ "$GPU_COUNT" == "0" || "$GPU_COUNT" == "null" ]]; then
      missing+=("GPU acceleration requested but no NVIDIA GPUs found in cluster. Either disable GPU settings or install NVIDIA GPU Operator and add GPU nodes.")
    fi
  fi

  # Check for sufficient cluster resources
  log_status "running" "validating" "Checking cluster capacity..."

  # Get total CPU cores across all nodes
  # CPU can be in format "8" (cores) or "8000m" (millicores)
  TOTAL_CPU=$(oc get nodes -o json 2>/dev/null | jq '
    [.items[].status.capacity.cpu] |
    map(
      if test("m$") then
        (rtrimstr("m") | tonumber / 1000)
      else
        tonumber
      end
    ) |
    add // 0' 2>/dev/null)

  # Get total memory in GiB
  # Memory is in format like "394938148Ki"
  TOTAL_MEM_KI=$(oc get nodes -o json 2>/dev/null | jq '
    [.items[].status.capacity.memory] |
    map(rtrimstr("Ki") | tonumber) |
    add // 0' 2>/dev/null)

  # Default to 0 if empty or null
  TOTAL_CPU=${TOTAL_CPU:-0}
  TOTAL_MEM_KI=${TOTAL_MEM_KI:-0}

  # Convert memory to GB
  if [[ "$TOTAL_MEM_KI" != "0" && "$TOTAL_MEM_KI" != "null" ]]; then
    TOTAL_MEM_GB=$(echo "scale=0; $TOTAL_MEM_KI / 1048576" | bc 2>/dev/null)
  else
    TOTAL_MEM_GB=0
  fi

  MIN_CPU=4
  MIN_MEM_GB=16

  # Check CPU (use bc for decimal comparison)
  if (( $(echo "$TOTAL_CPU < $MIN_CPU" | bc -l 2>/dev/null) )); then
    missing+=("Insufficient CPU: need ${MIN_CPU} cores, cluster has ${TOTAL_CPU} cores")
  fi

  # Check memory
  if [[ "$TOTAL_MEM_GB" -lt "$MIN_MEM_GB" ]]; then
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
