#!/bin/bash
# Deploy script for peoplemesh installer jobs
#
# Usage:
#   ./deploy.sh check_pre_reqs <namespace>          # Validate prerequisites
#   ./deploy.sh status <namespace>                   # Check deployment status
#   ./deploy.sh install <namespace>                  # Deploy installation
#   ./deploy.sh uninstall_keep_data <namespace>      # Uninstall (keep data)
#   ./deploy.sh uninstall_delete_all <namespace>     # Uninstall (delete all)
#
# Environment variables:
#   NAMESPACE    - Target namespace (can be set instead of passing as argument)

set -euo pipefail

# Configuration
REGISTRY="quay.io/rh-ai-quickstart"
IMAGE_NAME="peoplemesh-installer"
VERSION="1.0.0"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${VERSION}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() {
  echo -e "${GREEN}✓${NC} $1"
}

warn() {
  echo -e "${YELLOW}⚠${NC} $1"
}

error() {
  echo -e "${RED}✗${NC} $1"
  exit 1
}

# Function to deploy an action as a Kubernetes Job
deploy_job() {
  local ACTION=$1
  local TARGET_NAMESPACE=$2
  local EXTRA_ENV=$3  # Additional env vars as YAML snippet

  # Installer runs in 'default' namespace, manages resources in target namespace
  local INSTALLER_NAMESPACE="default"

  # Create RBAC for installer in default namespace only
  info "Creating installer RBAC..."
  cat <<RBAC | oc apply -f -
---
# Installer ServiceAccount in default namespace
apiVersion: v1
kind: ServiceAccount
metadata:
  name: peoplemesh-installer
  namespace: ${INSTALLER_NAMESPACE}
---
# Role in default namespace (for installer to manage its own pod resources)
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: peoplemesh-installer
  namespace: ${INSTALLER_NAMESPACE}
rules:
  - apiGroups: [""]
    resources: ["pods", "configmaps"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: peoplemesh-installer
  namespace: ${INSTALLER_NAMESPACE}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: peoplemesh-installer
subjects:
  - kind: ServiceAccount
    name: peoplemesh-installer
    namespace: ${INSTALLER_NAMESPACE}
RBAC

  # Create ClusterRole with all permissions needed for installation across namespaces
  # When bound via ClusterRoleBinding, namespace-scoped resource permissions apply to ALL namespaces
  cat <<RBAC | oc apply -f -
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: peoplemesh-installer-${TARGET_NAMESPACE}
rules:
  # Cluster-scoped read permissions for prerequisites checking
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list"]
  - apiGroups: ["config.openshift.io"]
    resources: ["clusterversions"]
    verbs: ["get", "list"]
  - apiGroups: ["apiextensions.k8s.io"]
    resources: ["customresourcedefinitions"]
    verbs: ["get", "list"]
  - apiGroups: ["packages.operators.coreos.com"]
    resources: ["packagemanifests"]
    verbs: ["get", "list"]
  # Namespace management
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "list", "create", "delete"]
  # Namespace-scoped resources (applies to ALL namespaces when bound via ClusterRoleBinding)
  - apiGroups: [""]
    resources: ["pods", "services", "secrets", "configmaps", "persistentvolumeclaims", "serviceaccounts"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets", "replicasets"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["route.openshift.io"]
    resources: ["routes"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["k8s.keycloak.org"]
    resources: ["keycloaks", "keycloakrealmimports"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["operators.coreos.com"]
    resources: ["clusterserviceversions", "subscriptions", "operatorgroups"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["roles", "rolebindings"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: peoplemesh-installer-${TARGET_NAMESPACE}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: peoplemesh-installer-${TARGET_NAMESPACE}
subjects:
  - kind: ServiceAccount
    name: peoplemesh-installer
    namespace: ${INSTALLER_NAMESPACE}
RBAC

  # Generate unique job name
  local JOB_NAME="peoplemesh-installer-$(echo $ACTION | tr '[:upper:]' '[:lower:]' | tr '_' '-')-$(date +%s)"

  info "Creating installer Job: $JOB_NAME"
  info "Action: $ACTION"
  info "Target namespace: $TARGET_NAMESPACE"
  info "Installer namespace: $INSTALLER_NAMESPACE"
  info "Image: ${FULL_IMAGE}"

  # Create the Job manifest in default namespace
  cat <<EOF | oc apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${INSTALLER_NAMESPACE}
  labels:
    app: peoplemesh-installer
    action: $(echo $ACTION | tr '[:upper:]' '[:lower:]' | tr '_' '-')
    target-namespace: ${TARGET_NAMESPACE}
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        app: peoplemesh-installer
        action: $(echo $ACTION | tr '[:upper:]' '[:lower:]' | tr '_' '-')
    spec:
      restartPolicy: Never
      serviceAccountName: peoplemesh-installer
      containers:
      - name: installer
        image: ${FULL_IMAGE}
        imagePullPolicy: Always
        env:
        - name: ACTION
          value: "${ACTION}"
        - name: TARGET_NAMESPACE
          value: "${TARGET_NAMESPACE}"
${EXTRA_ENV}
EOF

  echo ""
  info "Job created! Monitoring logs..."
  echo ""

  # Wait for pod to start
  sleep 3

  # Follow logs (Job is now in default namespace)
  oc logs -n "$INSTALLER_NAMESPACE" -f "job/${JOB_NAME}" 2>/dev/null || {
    warn "Job may still be starting. Check logs with:"
    echo "  oc logs -n $INSTALLER_NAMESPACE -f job/${JOB_NAME}"
  }

  echo ""
  info "Waiting for Job to complete..."

  # Wait for Job to reach a terminal state (Complete or Failed)
  # Poll every 5 seconds for up to 20 minutes
  WAIT_COUNT=0
  MAX_WAIT=240  # 20 minutes = 240 * 5 seconds
  while [[ $WAIT_COUNT -lt $MAX_WAIT ]]; do
    JOB_COMPLETE=$(oc get job -n "$INSTALLER_NAMESPACE" "${JOB_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null)
    JOB_FAILED=$(oc get job -n "$INSTALLER_NAMESPACE" "${JOB_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null)

    if [[ "$JOB_COMPLETE" == "True" ]]; then
      info "Job completed successfully"
      break
    elif [[ "$JOB_FAILED" == "True" ]]; then
      warn "Job failed. Check logs above for details."
      break
    fi

    sleep 5
    WAIT_COUNT=$((WAIT_COUNT + 1))
  done

  if [[ $WAIT_COUNT -eq $MAX_WAIT ]]; then
    warn "Job did not complete within 20 minutes"
    echo "  Check status: oc get job -n $INSTALLER_NAMESPACE ${JOB_NAME}"
  fi

  info "Job complete! Check status with:"
  echo "  oc get job -n $INSTALLER_NAMESPACE ${JOB_NAME}"
  echo "  oc describe job -n $INSTALLER_NAMESPACE ${JOB_NAME}"

  # Clean up all installer RBAC (created by this script)
  # Installer Job cleans up target namespace RBAC only
  info "Cleaning up installer RBAC..."

  # Clean up default namespace RBAC
  oc delete serviceaccount peoplemesh-installer -n default --ignore-not-found=true 2>/dev/null || true
  oc delete role peoplemesh-installer -n default --ignore-not-found=true 2>/dev/null || true
  oc delete rolebinding peoplemesh-installer -n default --ignore-not-found=true 2>/dev/null || true
  oc delete secret -l "kubernetes.io/service-account.name=peoplemesh-installer" -n default --ignore-not-found=true 2>/dev/null || true

  # Clean up cluster-scoped RBAC
  oc delete clusterrolebinding "peoplemesh-installer-${TARGET_NAMESPACE}" --ignore-not-found=true 2>/dev/null || true
  oc delete clusterrole "peoplemesh-installer-${TARGET_NAMESPACE}" --ignore-not-found=true 2>/dev/null || true
}

# Main logic based on action
case "${1:-}" in
  check_pre_reqs)
    NAMESPACE="${2:-${NAMESPACE:-}}"
    if [[ -z "$NAMESPACE" ]]; then
      error "Namespace required. Usage: ./deploy.sh check_pre_reqs <namespace>"
    fi
    deploy_job "CHECK_PRE_REQS" "$NAMESPACE" ""
    ;;

  status)
    NAMESPACE="${2:-${NAMESPACE:-}}"
    if [[ -z "$NAMESPACE" ]]; then
      error "Namespace required. Usage: ./deploy.sh status <namespace>"
    fi
    deploy_job "STATUS" "$NAMESPACE" ""
    ;;

  install)
    NAMESPACE="${2:-${NAMESPACE:-}}"
    if [[ -z "$NAMESPACE" ]]; then
      error "Namespace required. Usage: ./deploy.sh install <namespace>"
    fi

    # Prompt for test user password
    read -sp "Enter test user password: " TEST_PASSWORD
    echo ""

    if [[ -z "$TEST_PASSWORD" ]]; then
      error "Test user password is required"
    fi

    # Prompt for GPU acceleration
    echo ""
    echo "GPU Acceleration Options:"
    echo "Enabling GPU provides 10-20x speedup but requires NVIDIA GPU Operator."
    echo ""

    read -p "Enable GPU for Ollama (LLM inference)? [y/N]: " ENABLE_OLLAMA_GPU
    OLLAMA_GPU_ENABLED="false"
    if [[ "$ENABLE_OLLAMA_GPU" =~ ^[Yy]$ ]]; then
      OLLAMA_GPU_ENABLED="true"
    fi

    read -p "Enable GPU for Docling (document processing)? [y/N]: " ENABLE_DOCLING_GPU
    DOCLING_GPU_ENABLED="false"
    if [[ "$ENABLE_DOCLING_GPU" =~ ^[Yy]$ ]]; then
      DOCLING_GPU_ENABLED="true"
    fi

    echo ""

    INSTALL_ENV="        - name: INSTALL_MODE
          value: \"demo\"
        - name: PARAM_KEYCLOAK_REALM_TESTUSER_PASSWORD
          value: \"${TEST_PASSWORD}\"
        - name: PARAM_OLLAMA_GPU_ENABLED
          value: \"${OLLAMA_GPU_ENABLED}\"
        - name: PARAM_DOCLING_GPU_ENABLED
          value: \"${DOCLING_GPU_ENABLED}\""
    deploy_job "INSTALL" "$NAMESPACE" "$INSTALL_ENV"
    ;;

  uninstall_keep_data)
    NAMESPACE="${2:-${NAMESPACE:-}}"
    if [[ -z "$NAMESPACE" ]]; then
      error "Namespace required. Usage: ./deploy.sh uninstall_keep_data <namespace>"
    fi
    deploy_job "UNINSTALL_KEEP_DATA" "$NAMESPACE" ""
    ;;

  uninstall_delete_all)
    NAMESPACE="${2:-${NAMESPACE:-}}"
    if [[ -z "$NAMESPACE" ]]; then
      error "Namespace required. Usage: ./deploy.sh uninstall_delete_all <namespace>"
    fi
    deploy_job "UNINSTALL_DELETE_ALL" "$NAMESPACE" ""
    # Note: Installer Job cleans up all RBAC via EXIT trap
    ;;

  upgrade)
    NAMESPACE="${2:-${NAMESPACE:-}}"
    if [[ -z "$NAMESPACE" ]]; then
      error "Namespace required. Usage: ./deploy.sh upgrade <namespace>"
    fi

    # Note: UPGRADE action is not currently supported by the installer
    # This case exists to allow testing that the installer properly rejects unsupported actions
    UPGRADE_ENV="        - name: INSTALL_MODE
          value: \"demo\""
    deploy_job "UPGRADE" "$NAMESPACE" "$UPGRADE_ENV"
    ;;

  "")
    echo "Peoplemesh Installer - Deploy Jobs to Cluster"
    echo ""
    echo "Usage: ./deploy.sh <action> <namespace>"
    echo ""
    echo "Actions:"
    echo "  check_pre_reqs <namespace>          - Validate prerequisites"
    echo "  status <namespace>                   - Check deployment status"
    echo "  install <namespace>                  - Deploy installation"
    echo "  uninstall_keep_data <namespace>      - Uninstall (keep data)"
    echo "  uninstall_delete_all <namespace>     - Uninstall (delete all)"
    echo "  upgrade <namespace>                  - Upgrade installation (not supported yet)"
    echo ""
    echo "Note: Image must already be pushed to ${FULL_IMAGE}"
    echo "      Run ./build.sh push first if needed."
    ;;

  *)
    error "Unknown action: $1. Use: deploy.sh [check_pre_reqs|status|install|uninstall_keep_data|uninstall_delete_all|upgrade] <namespace>"
    ;;
esac
