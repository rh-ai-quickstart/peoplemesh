#!/bin/bash

cleanup_quickstart() {
  local cleanup_mode="${1:-delete-all}"  # delete-all | keep-data

  log_status "running" "uninstalling" "Cleanup mode: $cleanup_mode"

  # Uninstall Helm release
  log_status "running" "uninstalling" "Removing Helm release..."
  if helm list -n "$TARGET_NAMESPACE" 2>/dev/null | grep -q 'peoplemesh'; then
    helm uninstall peoplemesh -n "$TARGET_NAMESPACE" || true
    log_status "running" "uninstalling" "Helm release removed"
  else
    log_status "running" "uninstalling" "No Helm release found to remove"
  fi

  # Handle data volumes based on cleanup mode
  if [[ "$cleanup_mode" == "delete-all" ]]; then
    log_status "running" "uninstalling" "Deleting persistent volumes..."

    # Delete all PVCs in the namespace that belong to peoplemesh
    PVC_COUNT=$(oc get pvc -n "$TARGET_NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$PVC_COUNT" -gt 0 ]]; then
      oc delete pvc -n "$TARGET_NAMESPACE" --all --timeout=60s 2>/dev/null || true
      log_status "running" "uninstalling" "Deleted $PVC_COUNT persistent volume claim(s)"
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

  log_status "running" "uninstalling" "Cleanup complete"
}
