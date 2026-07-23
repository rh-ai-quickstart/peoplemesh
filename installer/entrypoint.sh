#!/bin/bash
set -euo pipefail

# Source helper functions
source /installer/lib/check_pre_reqs.sh
source /installer/lib/install.sh
source /installer/lib/upgrade.sh
source /installer/lib/status.sh
source /installer/lib/uninstall.sh

# Termination message state
_TERMINATION_STATUS=""
_TERMINATION_MESSAGE=""
_LOG_FILE="/tmp/installer-output.log"
: > "$_LOG_FILE"

# Save original stdout/stderr, then tee all output to a log file for ConfigMap persistence
exec 3>&1 4>&2
exec > >(tee -a "$_LOG_FILE") 2> >(tee -a "$_LOG_FILE" >&2)

# Logging functions for structured JSON output
log_status() {
  local status=$1
  local phase=$2
  local message=$3
  echo "{\"status\":\"$status\",\"phase\":\"$phase\",\"message\":\"$message\"}"
}

log_success() {
  local endpoints=$1
  _TERMINATION_STATUS="success"
  _TERMINATION_MESSAGE=""
  echo "{\"status\":\"success\",\"endpoints\":$endpoints}"
}

log_error() {
  local message=$1
  _TERMINATION_STATUS="error"
  _TERMINATION_MESSAGE="$message"
  echo "{\"status\":\"error\",\"message\":\"$message\"}" >&2
  exit 1
}

log_prerequisites_failed() {
  local missing_json=$1
  _TERMINATION_STATUS="prerequisites_failed"
  _TERMINATION_MESSAGE="$missing_json"
  echo "{\"status\":\"prerequisites_failed\",\"missing\":$missing_json}" >&2
  exit 2
}

cleanup_installer_rbac() {
  log_status "running" "cleanup" "Installer cleanup complete"
}

write_log_configmap() {
  local job_name="${JOB_NAME:-unknown}"
  local cm_name="peoplemesh-installer-log-${job_name}"
  local target_ns="${TARGET_NAMESPACE:-unknown}"
  # Use date-only format for label value (colons not allowed in label values)
  local expires_at
  expires_at=$(date -u -d "+7 days" '+%Y-%m-%d' 2>/dev/null || \
               date -u -v+7d '+%Y-%m-%d' 2>/dev/null || \
               echo "unknown")

  # Truncate log to fit ConfigMap size limits (1MB max, keep under 512KB to be safe)
  local log_content
  log_content=$(tail -c 500000 "$_LOG_FILE" 2>/dev/null || echo "")

  if [[ -z "$log_content" ]]; then
    return 0
  fi

  # Write log to temp file, then create ConfigMap from it
  local log_tmpfile="/tmp/installer-log-data.txt"
  echo "$log_content" > "$log_tmpfile"

  oc create configmap "$cm_name" \
    --namespace default \
    --from-file=log="$log_tmpfile" 2>/dev/null || { true; return 0; }

  oc label configmap "$cm_name" \
    --namespace default \
    --overwrite \
    "app=peoplemesh-installer" \
    "target-namespace=${target_ns}" \
    "peoplemesh-installer/expires-at=${expires_at}" 2>&1 || true
}

write_termination_message() {
  local exit_code=$1
  local status="${_TERMINATION_STATUS}"

  # Determine status from exit code if not explicitly set
  if [[ -z "$status" ]]; then
    case "$exit_code" in
      0) status="success" ;;
      2) status="prerequisites_failed" ;;
      *) status="error" ;;
    esac
  fi

  # Collect recent log lines for context
  local recent_logs
  recent_logs=$(tail -10 "$_LOG_FILE" 2>/dev/null | head -c 2000 || echo "")
  # Escape for JSON
  recent_logs="${recent_logs//\\/\\\\}"
  recent_logs="${recent_logs//\"/\\\"}"
  recent_logs="${recent_logs//$'\n'/\\n}"

  local job_name="${JOB_NAME:-unknown}"
  local cm_name="peoplemesh-installer-log-${job_name}"
  local action="${ACTION:-unknown}"
  local namespace="${TARGET_NAMESPACE:-unknown}"

  local message=""
  case "$status" in
    success)
      message="{\"status\":\"success\",\"action\":\"${action}\",\"namespace\":\"${namespace}\",\"logConfigMap\":{\"name\":\"${cm_name}\",\"namespace\":\"default\"}}"
      ;;
    prerequisites_failed)
      message="{\"status\":\"prerequisites_failed\",\"action\":\"${action}\",\"namespace\":\"${namespace}\",\"missing\":${_TERMINATION_MESSAGE:-[]},\"logConfigMap\":{\"name\":\"${cm_name}\",\"namespace\":\"default\"}}"
      ;;
    error)
      local err_msg="${_TERMINATION_MESSAGE:-Unexpected failure (exit code $exit_code)}"
      err_msg="${err_msg//\\/\\\\}"
      err_msg="${err_msg//\"/\\\"}"
      err_msg="${err_msg//$'\n'/\\n}"
      message="{\"status\":\"error\",\"action\":\"${action}\",\"namespace\":\"${namespace}\",\"message\":\"${err_msg}\",\"recentLogs\":\"${recent_logs}\",\"logConfigMap\":{\"name\":\"${cm_name}\",\"namespace\":\"default\"}}"
      ;;
  esac

  printf '%.4096s' "$message" > /dev/termination-log 2>/dev/null || true

  # Annotate the Job with the termination message for durable retrieval after pod cleanup
  if [[ -n "$job_name" && "$job_name" != "unknown" ]]; then
    oc annotate job "$job_name" \
      --namespace default \
      --overwrite \
      "peoplemesh-installer/termination-message=$message" 2>/dev/null || true
  fi
}

# EXIT trap - fires on every exit path
cleanup_on_exit() {
  local exit_code=$?
  # Close tee'd stdout/stderr so tee processes flush all buffered output,
  # then restore original file descriptors for EXIT trap output
  exec 1>&3 2>&4 3>&- 4>&-
  sleep 0.2
  # Run termination message and cleanup first, capturing their output to the log file
  write_termination_message "$exit_code" 2>&1 | tee -a "$_LOG_FILE"
  if [[ "$exit_code" -ne 2 ]]; then
    cleanup_installer_rbac 2>&1 | tee -a "$_LOG_FILE"
  fi
  # Write log ConfigMap last so it captures all prior output
  write_log_configmap
}
trap cleanup_on_exit EXIT

# Validate required environment variables
: "${ACTION:?ACTION must be set (CHECK_PRE_REQS|STATUS|INSTALL|UNINSTALL_DELETE_ALL|UNINSTALL_KEEP_DATA|UPGRADE)}"
: "${TARGET_NAMESPACE:?TARGET_NAMESPACE must be set}"
: "${INSTALL_MODE:=demo}"  # Default to demo mode if not specified

# Validate supported actions
case "$ACTION" in
  UPGRADE)
    log_error "Deployment Action (UPGRADE) not supported."
    ;;
esac

# Validate supported installation modes
if [[ "$INSTALL_MODE" != "demo" ]]; then
  log_error "Installation mode ($INSTALL_MODE) not supported. Only 'demo' mode is currently supported."
fi

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
