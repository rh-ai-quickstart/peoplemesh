#!/bin/bash

verify_deployment() {
  # Verify deployment state - works for both installed and uninstalled states
  # Returns deployment health information without waiting/retrying

  log_status "running" "verifying" "Checking namespace: $TARGET_NAMESPACE"

  # Check if namespace exists and its phase
  NAMESPACE_EXISTS=false
  NAMESPACE_PHASE=$(oc get namespace "$TARGET_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)

  if [[ -n "$NAMESPACE_PHASE" ]]; then
    NAMESPACE_EXISTS=true
    if [[ "$NAMESPACE_PHASE" == "Terminating" ]]; then
      log_status "running" "verifying" "Namespace is terminating"
    else
      log_status "running" "verifying" "Namespace exists"
    fi
  else
    log_status "running" "verifying" "Namespace does not exist - clean state"
    return 0
  fi

  # Check for Helm release
  HELM_STATUS=$(helm list -n "$TARGET_NAMESPACE" 2>/dev/null | grep 'peoplemesh' || echo "")

  if [[ -z "$HELM_STATUS" ]]; then
    log_status "running" "verifying" "No Helm release found"

    # Check for orphaned quickstart resources (exclude installer infrastructure)
    # Pods: Exclude completed Jobs and installer Jobs
    POD_COUNT=$(oc get pods -n "$TARGET_NAMESPACE" -o json 2>/dev/null | \
      jq '[.items[] | select(
        .status.phase != "Succeeded" and
        (.metadata.labels.app // "") != "peoplemesh-installer"
      )] | length' 2>/dev/null || echo "0")

    # PVCs: All PVCs are considered quickstart resources
    PVC_COUNT=$(oc get pvc -n "$TARGET_NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')

    # Secrets: Only count Helm-managed secrets (exclude OpenShift default secrets and installer secrets)
    SECRET_COUNT=$(oc get secret -n "$TARGET_NAMESPACE" -o json 2>/dev/null | \
      jq '[.items[] | select(
        ((.metadata.labels."app.kubernetes.io/managed-by" // "") == "Helm" or
         (.metadata.name | startswith("peoplemesh-")) or
         (.metadata.name | startswith("keycloak-"))) and
        (.metadata.name | startswith("peoplemesh-installer-") | not) and
        (.metadata.name | startswith("peoplemesh-cleanup-") | not)
      )] | length' 2>/dev/null || echo "0")

    if [[ "$POD_COUNT" -gt 0 || "$PVC_COUNT" -gt 0 || "$SECRET_COUNT" -gt 0 ]]; then
      log_status "running" "verifying" "Orphaned resources found: $POD_COUNT pods, $PVC_COUNT PVCs, $SECRET_COUNT secrets"
    else
      log_status "running" "verifying" "Clean uninstall verified - no quickstart resources found"
    fi
    return 0
  fi

  # Helm release exists - check deployment health
  log_status "running" "verifying" "Helm release found: $HELM_STATUS"

  # Check pod status
  TOTAL_PODS=$(oc get pods -n "$TARGET_NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
  RUNNING_PODS=$(oc get pods -n "$TARGET_NAMESPACE" -o json 2>/dev/null | \
    jq '[.items[] | select(.status.phase == "Running")] | length' 2>/dev/null || echo "0")
  READY_PODS=$(oc get pods -n "$TARGET_NAMESPACE" -o json 2>/dev/null | \
    jq '[.items[] | select(.status.phase == "Running" and (.status.conditions[]? | select(.type == "Ready" and .status == "True")))] | length' 2>/dev/null || echo "0")

  log_status "running" "verifying" "Pod status: $READY_PODS/$RUNNING_PODS/$TOTAL_PODS (ready/running/total)"

  # Check routes
  ROUTE_COUNT=$(oc get routes -n "$TARGET_NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
  log_status "running" "verifying" "Routes: $ROUTE_COUNT"

  # Check PVCs
  PVC_TOTAL=$(oc get pvc -n "$TARGET_NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
  PVC_BOUND=$(oc get pvc -n "$TARGET_NAMESPACE" -o json 2>/dev/null | \
    jq '[.items[] | select(.status.phase == "Bound")] | length' 2>/dev/null || echo "0")
  log_status "running" "verifying" "PVCs: $PVC_BOUND/$PVC_TOTAL (bound/total)"

  # Quick health check (no retries)
  ROUTE_HOST=$(oc get route peoplemesh -n "$TARGET_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
  if [[ -n "$ROUTE_HOST" ]]; then
    HEALTH_URL="https://$ROUTE_HOST/q/health/ready"
    if HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "$HEALTH_URL" 2>/dev/null); then
      log_status "running" "verifying" "Peoplemesh API health: HTTP $HTTP_CODE"
    else
      log_status "running" "verifying" "Peoplemesh API: unreachable"
    fi
  fi

  log_status "running" "verifying" "Deployment verification complete"
}

check_deployment_status() {
  # Wait for all pods to be ready
  log_status "running" "checking-status" "Waiting for pods to be ready (timeout: 15m)..."

  TIMEOUT=900  # 15 minutes
  ELAPSED=0
  INTERVAL=10

  while [[ $ELAPSED -lt $TIMEOUT ]]; do
    READY_PODS=$(oc get pods -n "$TARGET_NAMESPACE" -o json 2>/dev/null | \
      jq '[.items[] | select(.status.phase == "Running" and (.status.conditions[]? | select(.type == "Ready" and .status == "True")))] | length' 2>/dev/null || echo "0")

    # Count total pods excluding completed Jobs (Succeeded phase)
    TOTAL_PODS=$(oc get pods -n "$TARGET_NAMESPACE" -o json 2>/dev/null | \
      jq '[.items[] | select(.status.phase != "Succeeded")] | length' 2>/dev/null || echo "0")

    # We expect at least 6 core pods: peoplemesh, keycloak, keycloak-postgres, pgvector, ollama, docling
    # But actual count may vary based on configuration (e.g., ollama disabled in external mode)
    if [[ "$READY_PODS" -ge 5 && "$READY_PODS" -eq "$TOTAL_PODS" ]]; then
      log_status "running" "checking-status" "All pods ready ($READY_PODS/$TOTAL_PODS)"
      break
    fi

    log_status "running" "checking-status" "Waiting for pods... ($READY_PODS/$TOTAL_PODS ready)"
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
  done

  if [[ $ELAPSED -ge $TIMEOUT ]]; then
    log_error "Timeout waiting for pods to be ready. Check pod status with: oc get pods -n $TARGET_NAMESPACE"
  fi

  # Health check: Peoplemesh API
  log_status "running" "checking-status" "Checking Peoplemesh API health..."
  ROUTE_HOST=$(oc get route peoplemesh -n "$TARGET_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

  if [[ -z "$ROUTE_HOST" ]]; then
    log_error "Unable to retrieve Peoplemesh route. Check route with: oc get route peoplemesh -n $TARGET_NAMESPACE"
  fi

  HEALTH_URL="https://$ROUTE_HOST/q/health/ready"

  for i in {1..24}; do  # Try for 4 minutes (24 * 10s)
    if HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "$HEALTH_URL" 2>/dev/null); then
      if [[ "$HTTP_CODE" == "200" ]]; then
        log_status "running" "checking-status" "Peoplemesh API is healthy"
        break
      fi
    fi
    if [[ $i -eq 24 ]]; then
      log_error "Peoplemesh API health check failed after 4 minutes. URL: $HEALTH_URL"
    fi
    log_status "running" "checking-status" "Waiting for Peoplemesh API... (attempt $i/24)"
    sleep 10
  done

  # Health check: Keycloak
  log_status "running" "checking-status" "Checking Keycloak health..."
  KC_ROUTE_HOST=$(oc get route keycloak -n "$TARGET_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

  if [[ -z "$KC_ROUTE_HOST" ]]; then
    log_error "Unable to retrieve Keycloak route. Check route with: oc get route keycloak -n $TARGET_NAMESPACE"
  fi

  # Use /realms/master as health check endpoint (Keycloak doesn't expose /health/ready)
  KC_HEALTH_URL="https://$KC_ROUTE_HOST/realms/master"

  for i in {1..24}; do  # Try for 4 minutes
    if HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "$KC_HEALTH_URL" 2>/dev/null); then
      if [[ "$HTTP_CODE" == "200" ]]; then
        log_status "running" "checking-status" "Keycloak is healthy"
        break
      fi
    fi
    if [[ $i -eq 24 ]]; then
      log_error "Keycloak health check failed after 4 minutes. URL: $KC_HEALTH_URL"
    fi
    log_status "running" "checking-status" "Waiting for Keycloak... (attempt $i/24)"
    sleep 10
  done

  log_status "running" "checking-status" "All health checks passed"
}

get_endpoints() {
  ROUTE_HOST=$(oc get route peoplemesh -n "$TARGET_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
  KC_ROUTE_HOST=$(oc get route keycloak -n "$TARGET_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

  if [[ -z "$ROUTE_HOST" || -z "$KC_ROUTE_HOST" ]]; then
    log_error "Unable to retrieve routes for endpoints"
  fi

  cat <<EOF
[
  {
    "name": "main",
    "displayName": "Peoplemesh Application",
    "url": "https://$ROUTE_HOST",
    "description": "Main application UI",
    "authentication": "required"
  },
  {
    "name": "keycloak-admin",
    "displayName": "Keycloak Admin Console",
    "url": "https://$KC_ROUTE_HOST/admin",
    "description": "Keycloak administration console",
    "authentication": "admin"
  }
]
EOF
}
