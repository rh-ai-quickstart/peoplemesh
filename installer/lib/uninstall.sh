#!/bin/bash

# Source common constants
source /installer/lib/common.sh

# Function to uninstall Keycloak operator
uninstall_keycloak_operator() {
  log_status "running" "uninstalling" "Removing Keycloak Operator..."

  # Check if subscription exists
  if ! oc get "$OLM_SUBSCRIPTION_RESOURCE" "$KEYCLOAK_OPERATOR_NAME" -n "$TARGET_NAMESPACE" >/dev/null 2>&1; then
    log_status "running" "uninstalling" "Keycloak Operator subscription not found"
    return 0
  fi

  # Get CSV name before deleting subscription
  local csv_name=$(oc get "$OLM_SUBSCRIPTION_RESOURCE" "$KEYCLOAK_OPERATOR_NAME" -n "$TARGET_NAMESPACE" -o jsonpath='{.status.installedCSV}' 2>/dev/null)

  # Delete Subscription
  log_status "running" "uninstalling" "Deleting Keycloak Operator Subscription..."
  oc delete "$OLM_SUBSCRIPTION_RESOURCE" "$KEYCLOAK_OPERATOR_NAME" -n "$TARGET_NAMESPACE" --ignore-not-found=true

  # Delete CSV
  if [[ -n "$csv_name" && "$csv_name" != "null" ]]; then
    log_status "running" "uninstalling" "Deleting Keycloak Operator CSV ($csv_name)..."
    oc delete "$OLM_CSV_RESOURCE" "$csv_name" -n "$TARGET_NAMESPACE" --ignore-not-found=true
  fi

  # Delete OperatorGroup (namespace-scoped, safe to delete)
  log_status "running" "uninstalling" "Deleting OperatorGroup..."
  oc delete "$OLM_OPERATORGROUP_RESOURCE" --all -n "$TARGET_NAMESPACE" --ignore-not-found=true

  # Wait for operator pod to terminate
  log_status "running" "uninstalling" "Waiting for Keycloak Operator pod to terminate..."
  local waited=0
  local max_wait=60
  while [[ $waited -lt $max_wait ]]; do
    local op_pod_count=$(oc get pods -n "$TARGET_NAMESPACE" -l name=rhbk-operator --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$op_pod_count" -eq 0 ]]; then
      log_status "running" "uninstalling" "Keycloak Operator pod terminated"
      break
    fi
    log_status "running" "uninstalling" "Waiting for operator pod to terminate... ($op_pod_count remaining)"
    sleep 2
    waited=$((waited + 2))
  done

  log_status "running" "uninstalling" "Keycloak Operator removed"

  # Note: CRDs are intentionally NOT deleted (following OLM best practices)
  # CRD deletion is cascading and would delete all Keycloak instances cluster-wide
}

cleanup_quickstart() {
  local cleanup_mode="${1:-delete-all}"  # delete-all | keep-data

  log_status "running" "uninstalling" "Cleanup mode: $cleanup_mode"

  # Check if target namespace exists
  if ! oc get namespace "$TARGET_NAMESPACE" >/dev/null 2>&1; then
    log_status "running" "uninstalling" "Target namespace does not exist - nothing to uninstall"
    return 0
  fi

  log_status "running" "uninstalling" "Target namespace exists, proceeding with cleanup..."

  # Uninstall Helm release (this removes all pods, services, etc.)
  log_status "running" "uninstalling" "Removing Helm release..."
  if helm list -n "$TARGET_NAMESPACE" 2>/dev/null | grep -q 'peoplemesh'; then
    # Use --wait to ensure all resources are deleted before continuing
    helm uninstall peoplemesh -n "$TARGET_NAMESPACE" --wait --timeout 5m || {
      log_status "running" "uninstalling" "Helm uninstall encountered errors, continuing cleanup..."
    }
    log_status "running" "uninstalling" "Helm release removed"

    # Wait for all pods to terminate
    log_status "running" "uninstalling" "Waiting for pods to terminate..."
    local waited=0
    local max_wait=120
    while [[ $waited -lt $max_wait ]]; do
      local pod_count=$(oc get pods -n "$TARGET_NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
      if [[ "$pod_count" -eq 0 ]]; then
        log_status "running" "uninstalling" "All pods terminated"
        break
      fi
      log_status "running" "uninstalling" "Waiting for pods to terminate... ($pod_count remaining)"
      sleep 5
      waited=$((waited + 5))
    done
  else
    log_status "running" "uninstalling" "No Helm release found to remove"

    # Force cleanup orphaned resources (when Helm release is missing but resources remain)
    # Use label selectors to only delete quickstart resources, not operators or other infrastructure
    log_status "running" "uninstalling" "Checking for orphaned quickstart resources..."

    # Delete resources with Helm labels (app.kubernetes.io/managed-by=Helm)
    # This ensures we only delete resources created by our Helm chart
    log_status "running" "uninstalling" "Removing orphaned Helm-managed resources..."
    oc delete deployment,statefulset,service,route -n "$TARGET_NAMESPACE" \
      -l "app.kubernetes.io/managed-by=Helm" --wait=false 2>/dev/null || true

    # Delete Keycloak CRs by name (not all, to avoid affecting other Keycloaks)
    log_status "running" "uninstalling" "Removing Keycloak resources..."
    oc delete keycloak keycloak -n "$TARGET_NAMESPACE" --wait=false 2>/dev/null || true
    oc delete keycloakrealmimport peoplemesh-realm -n "$TARGET_NAMESPACE" --wait=false 2>/dev/null || true

    # Delete secrets by label (avoid deleting operator secrets)
    log_status "running" "uninstalling" "Removing quickstart secrets..."
    oc delete secret -n "$TARGET_NAMESPACE" \
      -l "app.kubernetes.io/managed-by=Helm" --wait=false 2>/dev/null || true

    # Delete configmaps by label
    log_status "running" "uninstalling" "Removing quickstart configmaps..."
    oc delete configmap -n "$TARGET_NAMESPACE" \
      -l "app.kubernetes.io/managed-by=Helm" --wait=false 2>/dev/null || true

    # Wait for quickstart pods to terminate (exclude operator and installer pods)
    log_status "running" "uninstalling" "Waiting for orphaned pods to terminate..."
    local waited=0
    local max_wait=180
    while [[ $waited -lt $max_wait ]]; do
      # Count pods but exclude operators and installers
      local pod_count=$(oc get pods -n "$TARGET_NAMESPACE" --no-headers 2>/dev/null | \
        grep -v "operator\|peoplemesh-installer" | wc -l | tr -d ' ')
      if [[ "$pod_count" -eq 0 ]]; then
        log_status "running" "uninstalling" "All orphaned pods terminated"
        break
      fi
      log_status "running" "uninstalling" "Waiting for orphaned pods to terminate... ($pod_count remaining)"
      sleep 5
      waited=$((waited + 5))
    done
  fi

  # Handle data volumes based on cleanup mode
  if [[ "$cleanup_mode" == "delete-all" ]]; then
    log_status "running" "uninstalling" "Deleting persistent volumes..."

    # Delete all PVCs in the namespace that belong to peoplemesh
    PVC_COUNT=$(oc get pvc -n "$TARGET_NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$PVC_COUNT" -gt 0 ]]; then
      log_status "running" "uninstalling" "Found $PVC_COUNT PVC(s) to delete..."

      # Delete PVCs without timeout - let them complete
      # Use --wait=false to avoid blocking, then wait separately
      oc delete pvc -n "$TARGET_NAMESPACE" --all --wait=false 2>/dev/null || true

      # Wait for PVCs to be deleted (up to 3 minutes)
      local waited=0
      local max_wait=180
      while [[ $waited -lt $max_wait ]]; do
        local remaining=$(oc get pvc -n "$TARGET_NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$remaining" -eq 0 ]]; then
          log_status "running" "uninstalling" "All PVCs deleted successfully"
          break
        fi
        log_status "running" "uninstalling" "Waiting for PVCs to delete... ($remaining remaining)"
        sleep 10
        waited=$((waited + 10))
      done

      # Check if any PVCs are still present
      local remaining=$(oc get pvc -n "$TARGET_NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
      if [[ "$remaining" -gt 0 ]]; then
        log_status "running" "uninstalling" "Warning: $remaining PVC(s) still terminating after ${max_wait}s"
      fi
    else
      log_status "running" "uninstalling" "No persistent volumes to delete"
    fi

    log_status "running" "uninstalling" "All quickstart data removed"
  else
    log_status "running" "uninstalling" "Keeping persistent volumes for future reinstall"

    # List PVCs that were kept
    PVC_LIST=$(oc get pvc -n "$TARGET_NAMESPACE" --no-headers 2>/dev/null | awk '{print $1}' | paste -sd "," - || echo "none")
    log_status "running" "uninstalling" "Preserved PVCs: $PVC_LIST"
  fi

  # Clean up orphaned Helm hook resources (ServiceAccounts that Helm doesn't remove on uninstall)
  log_status "running" "uninstalling" "Removing orphaned Helm hook resources..."
  oc delete serviceaccount peoplemesh-cleanup -n "$TARGET_NAMESPACE" 2>/dev/null || true

  # Handle operator and namespace based on cleanup mode
  if [[ "$cleanup_mode" == "delete-all" ]]; then
    # Delete operator (namespace-scoped, owned by quickstart)
    uninstall_keycloak_operator

    # Delete namespace (this cascades to any remaining resources)
    # NOTE: Cluster-scoped resources (ClusterRole, ClusterRoleBinding) will be orphaned because:
    # 1. Namespace deletion kills this Job before EXIT trap can run
    # 2. There's no way to delete them from within the Job due to circular RBAC dependency:
    #    - Deleting ClusterRoleBinding first → loses permission to delete ClusterRole
    #    - Deleting ClusterRole first → loses permission to delete ClusterRoleBinding
    # These orphaned resources must be cleaned up externally (by Navigator or manually):
    #   oc delete clusterrole peoplemesh-installer-<namespace>
    #   oc delete clusterrolebinding peoplemesh-installer-<namespace>
    log_status "running" "uninstalling" "Deleting namespace..."
    oc delete namespace "$TARGET_NAMESPACE" --ignore-not-found=true --wait=false 2>/dev/null || true

    # Wait briefly for namespace to start terminating
    sleep 5

    log_status "running" "uninstalling" "Namespace deletion initiated (may take a few minutes to fully complete)"
    log_status "running" "uninstalling" "All quickstart resources removed"
    log_status "running" "uninstalling" "Note: Cluster-scoped installer RBAC (ClusterRole, ClusterRoleBinding) must be cleaned up externally"
  else
    log_status "running" "uninstalling" "Keeping Keycloak Operator and namespace for future reinstall"
  fi

  log_status "running" "uninstalling" "Cleanup complete"
}
