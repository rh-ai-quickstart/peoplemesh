#!/bin/bash

verify_deployment() {
  # Wait for all pods to be ready
  log_status "running" "verifying" "Waiting for pods to be ready (timeout: 15m)..."

  TIMEOUT=900  # 15 minutes
  ELAPSED=0
  INTERVAL=10

  while [[ $ELAPSED -lt $TIMEOUT ]]; do
    READY_PODS=$(oc get pods -n "$TARGET_NAMESPACE" -o json 2>/dev/null | \
      jq '[.items[] | select(.status.phase == "Running" and (.status.conditions[]? | select(.type == "Ready" and .status == "True")))] | length' 2>/dev/null || echo "0")

    TOTAL_PODS=$(oc get pods -n "$TARGET_NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')

    # We expect at least 6 core pods: peoplemesh, keycloak, keycloak-postgres, pgvector, ollama, docling
    # But actual count may vary based on configuration (e.g., ollama disabled in external mode)
    if [[ "$READY_PODS" -ge 5 && "$READY_PODS" -eq "$TOTAL_PODS" ]]; then
      log_status "running" "verifying" "All pods ready ($READY_PODS/$TOTAL_PODS)"
      break
    fi

    log_status "running" "verifying" "Waiting for pods... ($READY_PODS/$TOTAL_PODS ready)"
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
  done

  if [[ $ELAPSED -ge $TIMEOUT ]]; then
    log_error "Timeout waiting for pods to be ready. Check pod status with: oc get pods -n $TARGET_NAMESPACE"
  fi

  # Health check: Peoplemesh API
  log_status "running" "verifying" "Checking Peoplemesh API health..."
  ROUTE_HOST=$(oc get route peoplemesh -n "$TARGET_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

  if [[ -z "$ROUTE_HOST" ]]; then
    log_error "Unable to retrieve Peoplemesh route. Check route with: oc get route peoplemesh -n $TARGET_NAMESPACE"
  fi

  HEALTH_URL="https://$ROUTE_HOST/q/health/ready"

  for i in {1..24}; do  # Try for 4 minutes (24 * 10s)
    if HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "$HEALTH_URL" 2>/dev/null); then
      if [[ "$HTTP_CODE" == "200" ]]; then
        log_status "running" "verifying" "Peoplemesh API is healthy"
        break
      fi
    fi
    if [[ $i -eq 24 ]]; then
      log_error "Peoplemesh API health check failed after 4 minutes. URL: $HEALTH_URL"
    fi
    log_status "running" "verifying" "Waiting for Peoplemesh API... (attempt $i/24)"
    sleep 10
  done

  # Health check: Keycloak
  log_status "running" "verifying" "Checking Keycloak health..."
  KC_ROUTE_HOST=$(oc get route keycloak -n "$TARGET_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

  if [[ -z "$KC_ROUTE_HOST" ]]; then
    log_error "Unable to retrieve Keycloak route. Check route with: oc get route keycloak -n $TARGET_NAMESPACE"
  fi

  KC_HEALTH_URL="https://$KC_ROUTE_HOST/health/ready"

  for i in {1..24}; do  # Try for 4 minutes
    if HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "$KC_HEALTH_URL" 2>/dev/null); then
      if [[ "$HTTP_CODE" == "200" ]]; then
        log_status "running" "verifying" "Keycloak is healthy"
        break
      fi
    fi
    if [[ $i -eq 24 ]]; then
      log_error "Keycloak health check failed after 4 minutes. URL: $KC_HEALTH_URL"
    fi
    log_status "running" "verifying" "Waiting for Keycloak... (attempt $i/24)"
    sleep 10
  done

  log_status "running" "verifying" "All health checks passed"
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
