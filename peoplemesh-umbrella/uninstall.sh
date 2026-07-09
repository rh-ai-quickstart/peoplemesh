#!/bin/sh
#
# Simple uninstall script for Peoplemesh Quickstart
# Compatible with sh, bash, zsh on Linux and macOS
#
# Usage: ./uninstall.sh --namespace <namespace>
#
# Required:
#   --namespace <name>            Namespace to uninstall from
#

set -e  # Exit on error

# Default values
NAMESPACE=""

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 --namespace <namespace>"
            echo ""
            echo "Required:"
            echo "  --namespace <name>            Namespace to uninstall from"
            echo ""
            echo "Example:"
            echo "  $0 --namespace peoplemesh-quickstart"
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

# Check for required commands
if ! command -v helm >/dev/null 2>&1; then
    echo "Error: helm command not found. Please install Helm 3.x."
    exit 1
fi

# Display configuration
echo ""
echo "Uninstalling Peoplemesh Quickstart"
echo "==================================="
echo "Namespace: $NAMESPACE"
echo ""
echo "This will remove all Peoplemesh components from the namespace."
echo "All data will be permanently deleted (database volumes, secrets, etc.)"
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Uninstall cancelled."
    exit 0
fi

echo ""
echo "Uninstalling Helm release..."

# Run Helm uninstall
helm uninstall peoplemesh --namespace "$NAMESPACE"

echo ""
echo "Peoplemesh has been uninstalled from namespace: $NAMESPACE"
echo ""
echo "Note: The namespace itself still exists. To delete it completely:"
echo "  oc delete namespace $NAMESPACE"
echo ""
