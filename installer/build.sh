#!/bin/bash
# Build script for peoplemesh installer container image
#
# Usage:
#   ./build.sh          # Build locally
#   ./build.sh push     # Build and push to registry
#   ./build.sh test     # Build and run prerequisite check

set -euo pipefail

# Configuration
REGISTRY="ghcr.io/rh-ai-quickstart"
IMAGE_NAME="peoplemesh-installer"
VERSION="1.0.0"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${VERSION}"
LATEST_IMAGE="${REGISTRY}/${IMAGE_NAME}:latest"

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

# Check we're in the right directory
if [[ ! -f "installer/Dockerfile" ]]; then
  error "Must be run from repository root (where quickstart-manifest.yaml is)"
fi

# Check required files exist
info "Checking required files..."
[[ -f "quickstart-manifest.yaml" ]] || error "quickstart-manifest.yaml not found"
[[ -f "installer/Dockerfile" ]] || error "installer/Dockerfile not found"
[[ -f "installer/entrypoint.sh" ]] || error "installer/entrypoint.sh not found"
[[ -d "installer/lib" ]] || error "installer/lib directory not found"
[[ -d "peoplemesh-umbrella" ]] || warn "peoplemesh-umbrella directory not found (chart will be missing from image)"

# Build the image
info "Building installer image: ${FULL_IMAGE}"
docker build \
  -t "${FULL_IMAGE}" \
  -f installer/Dockerfile \
  . || error "Docker build failed"

# Tag as latest
info "Tagging as latest: ${LATEST_IMAGE}"
docker tag "${FULL_IMAGE}" "${LATEST_IMAGE}"

info "Build complete!"
echo ""
echo "Image: ${FULL_IMAGE}"
echo "Also tagged: ${LATEST_IMAGE}"
echo ""

# Handle additional commands
case "${1:-}" in
  push)
    info "Pushing to registry..."
    docker push "${FULL_IMAGE}" || error "Push failed"
    docker push "${LATEST_IMAGE}" || error "Push of latest tag failed"
    info "Push complete!"
    ;;

  test)
    info "Running prerequisite check (no installation)..."
    echo ""

    if [[ ! -f "$HOME/.kube/config" ]]; then
      error "No kubeconfig found at $HOME/.kube/config"
    fi

    docker run --rm \
      -e ACTION=verify \
      -e TARGET_NAMESPACE=peoplemesh-test \
      -v "$HOME/.kube/config:/tmp/kubeconfig:ro" \
      -e KUBECONFIG=/tmp/kubeconfig \
      "${FULL_IMAGE}" || true

    echo ""
    info "Prerequisite check complete! Check output above for results."
    ;;

  install)
    info "Running full installation to peoplemesh-test namespace..."
    echo ""

    if [[ ! -f "$HOME/.kube/config" ]]; then
      error "No kubeconfig found at $HOME/.kube/config"
    fi

    docker run --rm \
      -e ACTION=install \
      -e TARGET_NAMESPACE=peoplemesh-test \
      -e INSTALL_MODE=demo \
      -e PARAM_OLLAMA_GPU_ENABLED=false \
      -e PARAM_DOCLING_GPU_ENABLED=false \
      -v "$HOME/.kube/config:/tmp/kubeconfig:ro" \
      -e KUBECONFIG=/tmp/kubeconfig \
      "${FULL_IMAGE}"

    echo ""
    info "Installation complete! Check output above for endpoint URLs."
    ;;

  uninstall)
    info "Uninstalling from peoplemesh-test namespace (keeping data)..."
    echo ""

    if [[ ! -f "$HOME/.kube/config" ]]; then
      error "No kubeconfig found at $HOME/.kube/config"
    fi

    docker run --rm \
      -e ACTION=uninstall-keep-data \
      -e TARGET_NAMESPACE=peoplemesh-test \
      -v "$HOME/.kube/config:/tmp/kubeconfig:ro" \
      -e KUBECONFIG=/tmp/kubeconfig \
      "${FULL_IMAGE}"

    echo ""
    info "Uninstall complete! PVCs preserved for future reinstall."
    ;;

  uninstall-all)
    info "Uninstalling from peoplemesh-test namespace (deleting all data)..."
    echo ""

    if [[ ! -f "$HOME/.kube/config" ]]; then
      error "No kubeconfig found at $HOME/.kube/config"
    fi

    docker run --rm \
      -e ACTION=uninstall-delete-all \
      -e TARGET_NAMESPACE=peoplemesh-test \
      -v "$HOME/.kube/config:/tmp/kubeconfig:ro" \
      -e KUBECONFIG=/tmp/kubeconfig \
      "${FULL_IMAGE}"

    echo ""
    info "Uninstall complete! All data deleted."
    ;;

  "")
    # Just build, already done above
    echo "Next steps:"
    echo "  ./build.sh push          - Push to registry"
    echo "  ./build.sh test          - Test prerequisite check (no install)"
    echo "  ./build.sh install       - Test full installation (keeps data)"
    echo "  ./build.sh uninstall     - Remove test installation (keep data)"
    echo "  ./build.sh uninstall-all - Remove test installation (delete all data)"
    ;;

  *)
    error "Unknown command: $1. Use: build.sh [push|test|install|uninstall|uninstall-all]"
    ;;
esac
