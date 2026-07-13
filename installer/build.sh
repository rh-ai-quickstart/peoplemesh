#!/bin/bash
# Build script for peoplemesh installer container image
#
# Usage:
#   ./build.sh        # Build locally
#   ./build.sh push   # Build and push to registry
#
# Environment variables:
#   REGISTRY    - Container registry (default: quay.io/rh-ai-quickstart)
#   VERSION     - Image version tag (default: 1.0.0)

set -euo pipefail

# Configuration
REGISTRY="${REGISTRY:-quay.io/rh-ai-quickstart}"
IMAGE_NAME="peoplemesh-installer"
VERSION="${VERSION:-1.0.0}"
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
[[ -d "peoplemesh-umbrella" ]] || error "peoplemesh-umbrella directory not found"

# Build Helm dependencies before creating Docker image
info "Building Helm chart dependencies..."
cd peoplemesh-umbrella
helm dependency update || error "Helm dependency update failed"
cd ..

# Build the image
info "Building installer image: ${FULL_IMAGE}"
# Target platform: linux/amd64 (OpenShift cluster nodes)
podman build \
  --platform linux/amd64 \
  -t "${FULL_IMAGE}" \
  -f installer/Dockerfile \
  . || error "Podman build failed"

# Tag as latest
info "Tagging as latest: ${LATEST_IMAGE}"
podman tag "${FULL_IMAGE}" "${LATEST_IMAGE}"

info "Build complete!"
echo ""
echo "Image: ${FULL_IMAGE}"
echo "Also tagged: ${LATEST_IMAGE}"
echo ""

# Handle push command
if [[ "${1:-}" == "push" ]]; then
  info "Pushing to registry..."
  podman push "${FULL_IMAGE}" || error "Push failed"
  podman push "${LATEST_IMAGE}" || error "Push of latest tag failed"
  info "Push complete!"
  echo ""
fi

# Show next steps
if [[ "${1:-}" != "push" ]]; then
  echo "Next steps:"
  echo "  ./installer/build.sh push                        - Push to registry"
  echo ""
  echo "Deploy to cluster:"
  echo "  ./installer/deploy.sh check_pre_reqs <namespace> - Validate prerequisites"
  echo "  ./installer/deploy.sh status <namespace>         - Check deployment status"
  echo "  ./installer/deploy.sh install <namespace>        - Deploy installation"
else
  echo "Image pushed to registry!"
  echo ""
  echo "Deploy to cluster:"
  echo "  ./installer/deploy.sh check_pre_reqs <namespace> - Validate prerequisites"
  echo "  ./installer/deploy.sh status <namespace>         - Check deployment status"
  echo "  ./installer/deploy.sh install <namespace>        - Deploy installation"
fi
