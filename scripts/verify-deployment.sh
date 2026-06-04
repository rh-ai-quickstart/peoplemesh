#!/bin/bash
# Peoplemesh deployment verification script

set -e

NAMESPACE="${NAMESPACE:-peoplemesh}"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================"
echo "Peoplemesh Deployment Verification"
echo "Namespace: $NAMESPACE"
echo "========================================"
echo ""

# Function to check pod status
check_pod() {
    local pod_label=$1
    local pod_name=$2

    echo -n "Checking $pod_name... "

    if oc get pods -n "$NAMESPACE" -l "$pod_label" &> /dev/null; then
        POD_STATUS=$(oc get pods -n "$NAMESPACE" -l "$pod_label" -o jsonpath='{.items[0].status.phase}')
        if [ "$POD_STATUS" == "Running" ]; then
            echo -e "${GREEN}✓ Running${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠ Status: $POD_STATUS${NC}"
            return 1
        fi
    else
        echo -e "${RED}✗ Not Found${NC}"
        return 1
    fi
}

# Function to check service
check_service() {
    local service_name=$1

    echo -n "Checking service $service_name... "

    if oc get service "$service_name" -n "$NAMESPACE" &> /dev/null; then
        echo -e "${GREEN}✓ Exists${NC}"
        return 0
    else
        echo -e "${RED}✗ Not Found${NC}"
        return 1
    fi
}

# Check namespace exists
echo -n "Checking namespace $NAMESPACE... "
if oc get namespace "$NAMESPACE" &> /dev/null; then
    echo -e "${GREEN}✓ Exists${NC}"
else
    echo -e "${RED}✗ Not Found${NC}"
    exit 1
fi
echo ""

# Check pods
echo "Pod Status:"
echo "----------"
check_pod "app.kubernetes.io/name=pgvector" "PostgreSQL"
check_pod "app.kubernetes.io/name=docling" "Docling"
check_pod "app=peoplemesh-llm" "vLLM (if enabled)"
check_pod "app.kubernetes.io/name=peoplemesh" "Peoplemesh Application"
echo ""

# Check services
echo "Service Status:"
echo "--------------"
check_service "pgvector-service"
check_service "docling-service"
check_service "peoplemesh-service"
echo ""

# Check route
echo "Route Status:"
echo "------------"
if oc get route peoplemesh -n "$NAMESPACE" &> /dev/null; then
    ROUTE_HOST=$(oc get route peoplemesh -n "$NAMESPACE" -o jsonpath='{.spec.host}')
    echo -e "Peoplemesh UI: ${GREEN}https://$ROUTE_HOST${NC}"
else
    echo -e "${YELLOW}⚠ Route not found or not enabled${NC}"
fi
echo ""

# Health checks
echo "Health Checks:"
echo "-------------"

# Check PostgreSQL
echo -n "PostgreSQL database... "
if oc exec -it statefulset/pgvector -n "$NAMESPACE" -- psql -U peoplemesh -d peoplemesh -c "SELECT 1;" &> /dev/null; then
    echo -e "${GREEN}✓ Connected${NC}"
else
    echo -e "${RED}✗ Connection failed${NC}"
fi

# Check Docling
echo -n "Docling service... "
DOCLING_POD=$(oc get pods -n "$NAMESPACE" -l app.kubernetes.io/name=docling -o jsonpath='{.items[0].metadata.name}')
if [ -n "$DOCLING_POD" ]; then
    if oc exec -it "$DOCLING_POD" -n "$NAMESPACE" -- curl -sf http://localhost:5001/health &> /dev/null; then
        echo -e "${GREEN}✓ Healthy${NC}"
    else
        echo -e "${RED}✗ Health check failed${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Pod not found${NC}"
fi

# Check Peoplemesh
echo -n "Peoplemesh application... "
PEOPLEMESH_POD=$(oc get pods -n "$NAMESPACE" -l app.kubernetes.io/name=peoplemesh -o jsonpath='{.items[0].metadata.name}')
if [ -n "$PEOPLEMESH_POD" ]; then
    if oc exec -it "$PEOPLEMESH_POD" -n "$NAMESPACE" -- curl -sf http://localhost:8080/q/health &> /dev/null; then
        echo -e "${GREEN}✓ Healthy${NC}"
    else
        echo -e "${RED}✗ Health check failed${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Pod not found${NC}"
fi

echo ""
echo "========================================"
echo "Verification Complete"
echo "========================================"
echo ""
echo "Next steps:"
echo "  1. Visit the Peoplemesh UI: https://$ROUTE_HOST"
echo "  2. Retrieve maintenance key:"
echo "     oc get secret peoplemesh-secrets -n $NAMESPACE -o jsonpath='{.data.MAINTENANCE_API_KEY}' | base64 -d"
echo "  3. View logs:"
echo "     oc logs -f deployment/peoplemesh -n $NAMESPACE"
echo ""
