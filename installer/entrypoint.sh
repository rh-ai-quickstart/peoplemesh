#!/bin/bash
set -euo pipefail

# Source helper functions
source /installer/lib/prerequisites.sh
source /installer/lib/deploy.sh
source /installer/lib/upgrade.sh
source /installer/lib/verify.sh
source /installer/lib/cleanup.sh

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

# Validate required environment variables
: "${ACTION:?ACTION must be set (verify|install|upgrade|uninstall-delete-all|uninstall-keep-data)}"
: "${TARGET_NAMESPACE:?TARGET_NAMESPACE must be set}"
: "${INSTALL_MODE:=demo}"  # Default to demo mode if not specified

# Main logic based on ACTION
case "$ACTION" in
  verify)
    log_status "running" "validating" "Checking prerequisites..."
    check_prerequisites || exit 2
    log_status "success" "validating" "All prerequisites satisfied"
    log_success "[]"
    ;;

  install)
    log_status "running" "validating" "Validating prerequisites..."
    check_prerequisites || exit 2

    log_status "running" "deploying" "Installing in $INSTALL_MODE mode..."
    deploy_quickstart

    log_status "running" "verifying" "Waiting for pods to be ready..."
    verify_deployment

    log_status "running" "finalizing" "Retrieving endpoints..."
    ENDPOINTS=$(get_endpoints)
    log_success "$ENDPOINTS"
    ;;

  upgrade)
    # Validate upgrade-specific environment variables
    : "${SOURCE_VERSION:?SOURCE_VERSION required for upgrade}"
    : "${TARGET_VERSION:?TARGET_VERSION required for upgrade}"

    log_status "running" "validating" "Validating upgrade prerequisites..."
    check_prerequisites || exit 2

    log_status "running" "upgrading" "Upgrading from $SOURCE_VERSION to $TARGET_VERSION..."
    upgrade_quickstart

    log_status "running" "finalizing" "Retrieving endpoints..."
    ENDPOINTS=$(get_endpoints)
    log_success "$ENDPOINTS"
    ;;

  uninstall-delete-all)
    log_status "running" "uninstalling" "Removing quickstart and all data..."
    cleanup_quickstart "delete-all"
    log_success "[]"
    ;;

  uninstall-keep-data)
    log_status "running" "uninstalling" "Removing quickstart (keeping data volumes)..."
    cleanup_quickstart "keep-data"
    log_success "[]"
    ;;

  *)
    log_error "Invalid ACTION: $ACTION (must be verify|install|upgrade|uninstall-delete-all|uninstall-keep-data)"
    ;;
esac
