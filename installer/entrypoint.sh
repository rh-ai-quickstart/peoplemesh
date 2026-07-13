#!/bin/bash
set -euo pipefail

# Source helper functions
source /installer/lib/check_pre_reqs.sh
source /installer/lib/install.sh
source /installer/lib/upgrade.sh
source /installer/lib/status.sh
source /installer/lib/uninstall.sh

# Logging functions for structured JSON output
log_status() {
  local status=$1
  local phase=$2
  local message=$3
  echo "{\"status\":\"$status\",\"phase\":\"$phase\",\"message\":\"$message\"}"
}

log_success() {
  local endpoints=$1
  echo "{\"status\":\"success\",\"endpoints\":$endpoints}"
}

log_error() {
  local message=$1
  echo "{\"status\":\"error\",\"message\":\"$message\"}" >&2
  exit 1
}

log_prerequisites_failed() {
  local missing_json=$1
  echo "{\"status\":\"prerequisites_failed\",\"missing\":$missing_json}" >&2
  exit 2
}

cleanup_installer_rbac() {
  # Installer no longer creates or cleans up any RBAC
  # deploy.sh manages all RBAC (default namespace + cluster-scoped)
  # This function is kept for potential future cleanup tasks
  log_status "running" "cleanup" "Installer cleanup complete"
}

# Validate required environment variables
: "${ACTION:?ACTION must be set (CHECK_PRE_REQS|STATUS|INSTALL|UNINSTALL_DELETE_ALL|UNINSTALL_KEEP_DATA|UPGRADE)}"
: "${TARGET_NAMESPACE:?TARGET_NAMESPACE must be set}"
: "${INSTALL_MODE:=demo}"  # Default to demo mode if not specified

# Trap to ensure cleanup happens even on error (except for prerequisites failure)
cleanup_on_exit() {
  local exit_code=$?
  if [[ "$exit_code" -ne 2 ]]; then  # Don't cleanup on prerequisites failure (exit 2)
    cleanup_installer_rbac
  fi
}
trap cleanup_on_exit EXIT

# Main logic based on ACTION
case "$ACTION" in
  CHECK_PRE_REQS)
    log_status "running" "validating" "Validating prerequisites..."
    check_prerequisites || exit 2
    log_status "success" "validating" "All prerequisites satisfied"
    log_success "[]"
    ;;

  STATUS)
    log_status "running" "verifying" "Verifying quickstart deployment status..."
    verify_deployment
    log_status "success" "verifying" "Verification complete"
    log_success "[]"
    ;;

  INSTALL)
    log_status "running" "validating" "Validating prerequisites..."
    check_prerequisites || exit 2

    log_status "running" "deploying" "Installing in $INSTALL_MODE mode..."
    deploy_quickstart

    log_status "running" "checking-status" "Waiting for pods to be ready..."
    check_deployment_status

    log_status "running" "finalizing" "Retrieving endpoints..."
    ENDPOINTS=$(get_endpoints)
    log_success "$ENDPOINTS"
    ;;

  UNINSTALL_DELETE_ALL)
    log_status "running" "uninstalling" "Removing quickstart and all data..."
    cleanup_quickstart "delete-all"

    log_status "running" "verifying" "Verifying clean uninstallation..."
    verify_deployment
    log_success "[]"
    ;;

  UNINSTALL_KEEP_DATA)
    log_status "running" "uninstalling" "Removing quickstart (keeping data volumes)..."
    cleanup_quickstart "keep-data"

    log_status "running" "verifying" "Verifying uninstallation (data preserved)..."
    verify_deployment
    log_success "[]"
    ;;

  UPGRADE)
    log_status "running" "upgrading" "Upgrading quickstart..."
    upgrade_quickstart
    log_status "success" "upgrading" "Upgrade complete"
    log_success "[]"
    ;;

  *)
    log_error "Invalid ACTION: $ACTION (must be CHECK_PRE_REQS|STATUS|INSTALL|UNINSTALL_DELETE_ALL|UNINSTALL_KEEP_DATA|UPGRADE)"
    ;;
esac
