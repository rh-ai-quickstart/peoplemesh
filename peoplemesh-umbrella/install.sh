#!/bin/sh
#
# Simple deployment script for Peoplemesh Quickstart
# Compatible with sh, bash, zsh on Linux and macOS
#
# Usage: ./install.sh --namespace <namespace> --test-password <password> [OPTIONS]
#
# Required:
#   --namespace <name>            Target namespace for deployment
#   --test-password <password>    Password for test user login
#
# Optional:
#   --ollama-gpu <true|false>     Enable GPU for Ollama (default: false)
#   --docling-gpu <true|false>    Enable GPU for Docling (default: false)
#

set -e  # Exit on error

# Default values
NAMESPACE=""
OLLAMA_GPU="false"
DOCLING_GPU="false"
TEST_PASSWORD=""

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --ollama-gpu)
            OLLAMA_GPU="$2"
            shift 2
            ;;
        --docling-gpu)
            DOCLING_GPU="$2"
            shift 2
            ;;
        --test-password)
            TEST_PASSWORD="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 --namespace <namespace> --test-password <password> [OPTIONS]"
            echo ""
            echo "Required:"
            echo "  --namespace <name>            Target namespace for deployment"
            echo "  --test-password <password>    Password for test user login"
            echo ""
            echo "Optional:"
            echo "  --ollama-gpu <true|false>     Enable GPU for Ollama (default: false)"
            echo "  --docling-gpu <true|false>    Enable GPU for Docling (default: false)"
            echo ""
            echo "Example:"
            echo "  $0 --namespace peoplemesh-quickstart --test-password MySecurePassword"
            echo "  $0 --namespace my-namespace --test-password MySecurePassword --ollama-gpu true"
            exit 0
            ;;
        *)
            echo "Error: Unknown option $1"
            echo "Run '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$NAMESPACE" ]; then
    echo "Error: --namespace is required"
    echo "Run '$0 --help' for usage information"
    exit 1
fi

if [ -z "$TEST_PASSWORD" ]; then
    echo "Error: --test-password is required"
    echo "Run '$0 --help' for usage information"
    exit 1
fi

# Check for required commands
if ! command -v openssl >/dev/null 2>&1; then
    echo "Error: openssl command not found. Please install openssl."
    exit 1
fi

if ! command -v helm >/dev/null 2>&1; then
    echo "Error: helm command not found. Please install Helm 3.x."
    exit 1
fi

# Generate secure secrets (not exported to environment)
echo "Generating secure secrets..."
KC_DB_PASSWORD=$(openssl rand -base64 24)
PG_DB_PASSWORD=$(openssl rand -base64 24)
CLIENT_SECRET=$(openssl rand -base64 24)
SESSION_SECRET=$(openssl rand -base64 24)
OAUTH_SECRET=$(openssl rand -base64 24)
MAINT_KEY=$(openssl rand -base64 24)

# Display configuration
echo ""
echo "Deploying Peoplemesh Quickstart"
echo "================================"
echo "Namespace:    $NAMESPACE"
echo "Ollama GPU:   $OLLAMA_GPU"
echo "Docling GPU:  $DOCLING_GPU"
echo ""

# Run Helm install
helm install peoplemesh . \
  --namespace "$NAMESPACE" \
  --timeout 15m \
  --wait \
  --set keycloak.postgres.password="$KC_DB_PASSWORD" \
  --set pgvector.postgres.password="$PG_DB_PASSWORD" \
  --set keycloak.realm.client.clientSecret="$CLIENT_SECRET" \
  --set peoplemesh.security.sessionSecret="$SESSION_SECRET" \
  --set peoplemesh.security.oauthStateSecret="$OAUTH_SECRET" \
  --set peoplemesh.security.maintenanceApiKey="$MAINT_KEY" \
  --set keycloak.realm.testUser.password="$TEST_PASSWORD" \
  --set ollama.gpu.enabled="$OLLAMA_GPU" \
  --set docling.gpu.enabled="$DOCLING_GPU"

INSTALL_EXIT_CODE=$?

# Clear sensitive variables from memory
KC_DB_PASSWORD=""
PG_DB_PASSWORD=""
CLIENT_SECRET=""
SESSION_SECRET=""
OAUTH_SECRET=""
MAINT_KEY=""
TEST_PASSWORD=""

exit $INSTALL_EXIT_CODE
