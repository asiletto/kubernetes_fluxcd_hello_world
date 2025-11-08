#!/bin/bash

# Configuration
REGISTRY_HOST="${REGISTRY_HOST:-localhost}"
REGISTRY_PORT="${REGISTRY_PORT:-5000}"
CHARTMUSEUM_HOST="${CHARTMUSEUM_HOST:-localhost}"
CHARTMUSEUM_PORT="${CHARTMUSEUM_PORT:-8080}"

REGISTRY_URL="http://${REGISTRY_HOST}:${REGISTRY_PORT}"
CHARTMUSEUM_URL="http://${CHARTMUSEUM_HOST}:${CHARTMUSEUM_PORT}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Repository Proxies Verification"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  Docker Registry: ${REGISTRY_URL}"
echo "  ChartMuseum:     ${CHARTMUSEUM_URL}"
echo ""

# Track overall status
OVERALL_STATUS=0

# Function to print test result
print_result() {
    local status=$1
    local message=$2

    if [ $status -eq 0 ]; then
        echo -e "${GREEN}✓${NC} ${message}"
    else
        echo -e "${RED}✗${NC} ${message}"
        OVERALL_STATUS=1
    fi
}

# Function to print warning
print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Test 1: Docker Registry connectivity
echo "Testing Docker Registry..."
if curl -sf "${REGISTRY_URL}/v2/" > /dev/null 2>&1; then
    print_result 0 "Docker Registry is accessible"

    # Check catalog
    CATALOG=$(curl -s "${REGISTRY_URL}/v2/_catalog" 2>/dev/null)
    if echo "$CATALOG" | grep -q "repositories"; then
        REPO_COUNT=$(echo "$CATALOG" | grep -o '"[^"]*"' | wc -l)
        print_result 0 "Docker Registry catalog accessible ($(($REPO_COUNT / 2)) repositories cached)"
    else
        print_warning "Docker Registry catalog is empty (no images cached yet)"
    fi
else
    print_result 1 "Docker Registry is NOT accessible at ${REGISTRY_URL}"
fi
echo ""

# Test 2: ChartMuseum connectivity
echo "Testing ChartMuseum..."
if curl -sf "${CHARTMUSEUM_URL}/health" > /dev/null 2>&1; then
    print_result 0 "ChartMuseum is accessible"

    # Check available charts
    CHARTS=$(curl -s "${CHARTMUSEUM_URL}/api/charts" 2>/dev/null)
    if [ -n "$CHARTS" ] && [ "$CHARTS" != "{}" ]; then
        CHART_NAMES=$(echo "$CHARTS" | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"$//' | sort -u)
        CHART_COUNT=$(echo "$CHART_NAMES" | wc -l)
        print_result 0 "ChartMuseum has ${CHART_COUNT} chart(s):"
        echo "$CHART_NAMES" | while read -r chart; do
            echo "    - $chart"
        done
    else
        print_warning "ChartMuseum is empty (no charts uploaded yet)"
        echo "    Run: ./proxy-setup/populate-chartmuseum.sh"
    fi
else
    print_result 1 "ChartMuseum is NOT accessible at ${CHARTMUSEUM_URL}"
fi
echo ""

# Test 3: K3s registry mirrors configuration (requires root)
echo "Testing K3s Configuration..."
if [ -f /etc/rancher/k3s/registries.yaml ]; then
    print_result 0 "K3s registry mirrors configured"

    # Check if it contains the registry URL
    if grep -q "${REGISTRY_HOST}" /etc/rancher/k3s/registries.yaml 2>/dev/null; then
        print_result 0 "Registry mirrors point to ${REGISTRY_HOST}"
    else
        print_warning "Registry mirrors may not be configured correctly"
        echo "    Check: /etc/rancher/k3s/registries.yaml"
    fi
else
    print_warning "K3s registry mirrors NOT configured"
    echo "    Run: sudo REGISTRY_HOST=${REGISTRY_HOST} ./setup-registry-mirrors.sh"
fi
echo ""

# Test 4: FluxCD HelmRepository configuration
echo "Testing FluxCD Configuration..."
if [ -f infrastructure/sources/helm-repos.yaml ]; then
    if grep -q "CHARTMUSEUM_HOST" infrastructure/sources/helm-repos.yaml 2>/dev/null; then
        print_warning "HelmRepository URLs still contain CHARTMUSEUM_HOST placeholder"
        echo "    Update infrastructure/sources/helm-repos.yaml with actual ChartMuseum URL"
    elif grep -q "${CHARTMUSEUM_HOST}" infrastructure/sources/helm-repos.yaml 2>/dev/null; then
        print_result 0 "HelmRepository sources configured for ChartMuseum"
    else
        print_warning "HelmRepository sources may not be configured for ChartMuseum"
        echo "    Check: infrastructure/sources/helm-repos.yaml"
    fi
else
    print_result 1 "HelmRepository configuration file not found"
fi
echo ""

# Test 5: Test image pull through registry (if docker is available)
if command -v docker &> /dev/null; then
    echo "Testing Image Pull through Registry..."
    echo "  Pulling nginx:1.27-alpine through proxy..."

    if docker pull "${REGISTRY_HOST}:${REGISTRY_PORT}/library/nginx:1.27-alpine" > /dev/null 2>&1; then
        print_result 0 "Successfully pulled image through Docker Registry proxy"
        echo "    Check registry logs: docker logs docker-registry"
    else
        print_warning "Failed to pull image through registry proxy"
        echo "    This is expected if K3s mirrors are not configured"
        echo "    Or if the registry is not accessible from this host"
    fi
    echo ""
fi

# Test 6: FluxCD sources (if kubectl is available and cluster is accessible)
if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null; then
    echo "Testing FluxCD Sources in Cluster..."

    # Check HelmRepository sources
    HELM_SOURCES=$(kubectl get helmrepository -n flux-system -o json 2>/dev/null)
    if [ -n "$HELM_SOURCES" ]; then
        READY_COUNT=$(echo "$HELM_SOURCES" | grep -o '"ready":true' | wc -l)
        TOTAL_COUNT=$(echo "$HELM_SOURCES" | grep -o '"kind":"HelmRepository"' | wc -l)

        if [ $READY_COUNT -eq $TOTAL_COUNT ] && [ $TOTAL_COUNT -gt 0 ]; then
            print_result 0 "All HelmRepository sources are Ready (${READY_COUNT}/${TOTAL_COUNT})"
        else
            print_warning "Some HelmRepository sources are not Ready (${READY_COUNT}/${TOTAL_COUNT})"
            echo "    Check: flux get sources helm -A"
        fi
    else
        print_warning "No HelmRepository sources found or unable to check"
    fi
    echo ""
else
    print_warning "kubectl not available or cluster not accessible - skipping FluxCD checks"
    echo ""
fi

# Summary
echo "=========================================="
echo "Verification Summary"
echo "=========================================="
if [ $OVERALL_STATUS -eq 0 ]; then
    echo -e "${GREEN}✓ All critical checks passed${NC}"
    echo ""
    echo "Your repository proxy setup is working correctly!"
else
    echo -e "${RED}✗ Some checks failed${NC}"
    echo ""
    echo "Please review the warnings and errors above."
    echo "See CLAUDE.md section 'Local Repository Proxies' for troubleshooting."
fi
echo ""

exit $OVERALL_STATUS
