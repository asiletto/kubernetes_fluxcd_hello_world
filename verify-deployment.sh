#!/bin/bash

set -e

echo "======================================"
echo "FluxCD Deployment Verification"
echo "======================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    if command -v k3s &> /dev/null; then
        KUBECTL="sudo k3s kubectl"
    else
        echo -e "${RED}✗ kubectl not found${NC}"
        exit 1
    fi
else
    KUBECTL="kubectl"
fi

# Set KUBECONFIG
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

# Check if flux CLI is installed
FLUX_AVAILABLE=false
if command -v flux &> /dev/null; then
    FLUX_AVAILABLE=true
fi

echo "======================================"
echo "1. Cluster Status"
echo "======================================"
$KUBECTL cluster-info | head -n 2
echo ""

echo "======================================"
echo "2. FluxCD Components"
echo "======================================"
if [ "$FLUX_AVAILABLE" = true ]; then
    flux check
    echo ""
    echo "Flux Kustomizations:"
    flux get kustomizations
    echo ""
    echo "Flux Sources:"
    flux get sources git
else
    echo -e "${YELLOW}flux CLI not installed, showing kubectl output${NC}"
    echo ""
    $KUBECTL get pods -n flux-system
fi

echo ""
echo "======================================"
echo "3. Infrastructure Components"
echo "======================================"

echo ""
echo "--- Namespaces ---"
$KUBECTL get namespaces | grep -E "NAME|ingress-nginx|cert-manager|nginx-red|nginx-blue"

echo ""
echo "--- NGINX Ingress Controller ---"
if [ "$FLUX_AVAILABLE" = true ]; then
    flux get helmreleases -n ingress-nginx
fi
$KUBECTL get pods -n ingress-nginx
$KUBECTL get svc -n ingress-nginx ingress-nginx-controller

echo ""
echo "--- cert-manager ---"
if [ "$FLUX_AVAILABLE" = true ]; then
    flux get helmreleases -n cert-manager
fi
$KUBECTL get pods -n cert-manager

echo ""
echo "--- ClusterIssuers ---"
$KUBECTL get clusterissuers

echo ""
echo "======================================"
echo "4. Application Components"
echo "======================================"

echo ""
echo "--- nginx-red ---"
$KUBECTL get pods -n nginx-red
$KUBECTL get svc -n nginx-red
$KUBECTL get ingress -n nginx-red

echo ""
echo "--- nginx-blue ---"
$KUBECTL get pods -n nginx-blue
$KUBECTL get svc -n nginx-blue
$KUBECTL get ingress -n nginx-blue

echo ""
echo "======================================"
echo "5. Certificates"
echo "======================================"
$KUBECTL get certificates -A

echo ""
echo "Certificate Details:"
$KUBECTL get certificaterequests -A

echo ""
echo "======================================"
echo "6. Ingress Status"
echo "======================================"
$KUBECTL get ingress -A

echo ""
echo "======================================"
echo "7. Quick Health Summary"
echo "======================================"
echo ""

# Check infrastructure pods
INFRA_PODS_READY=0
INFRA_PODS_TOTAL=0

for ns in ingress-nginx cert-manager; do
    READY=$($KUBECTL get pods -n $ns --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    TOTAL=$($KUBECTL get pods -n $ns --no-headers 2>/dev/null | wc -l || echo "0")
    INFRA_PODS_READY=$((INFRA_PODS_READY + READY))
    INFRA_PODS_TOTAL=$((INFRA_PODS_TOTAL + TOTAL))
done

if [ $INFRA_PODS_READY -eq $INFRA_PODS_TOTAL ] && [ $INFRA_PODS_TOTAL -gt 0 ]; then
    echo -e "${GREEN}✓ Infrastructure: $INFRA_PODS_READY/$INFRA_PODS_TOTAL pods running${NC}"
else
    echo -e "${YELLOW}⚠ Infrastructure: $INFRA_PODS_READY/$INFRA_PODS_TOTAL pods running${NC}"
fi

# Check application pods
APP_PODS_READY=0
APP_PODS_TOTAL=0

for ns in nginx-red nginx-blue; do
    READY=$($KUBECTL get pods -n $ns --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    TOTAL=$($KUBECTL get pods -n $ns --no-headers 2>/dev/null | wc -l || echo "0")
    APP_PODS_READY=$((APP_PODS_READY + READY))
    APP_PODS_TOTAL=$((APP_PODS_TOTAL + TOTAL))
done

if [ $APP_PODS_READY -eq $APP_PODS_TOTAL ] && [ $APP_PODS_TOTAL -gt 0 ]; then
    echo -e "${GREEN}✓ Applications: $APP_PODS_READY/$APP_PODS_TOTAL pods running${NC}"
else
    echo -e "${YELLOW}⚠ Applications: $APP_PODS_READY/$APP_PODS_TOTAL pods running${NC}"
fi

# Check certificates
CERTS_READY=$($KUBECTL get certificates -A --no-headers 2>/dev/null | grep -c "True" || echo "0")
CERTS_TOTAL=$($KUBECTL get certificates -A --no-headers 2>/dev/null | wc -l || echo "0")

if [ $CERTS_READY -eq $CERTS_TOTAL ] && [ $CERTS_TOTAL -gt 0 ]; then
    echo -e "${GREEN}✓ Certificates: $CERTS_READY/$CERTS_TOTAL ready${NC}"
else
    echo -e "${YELLOW}⚠ Certificates: $CERTS_READY/$CERTS_TOTAL ready${NC}"
    if [ $CERTS_TOTAL -gt 0 ] && [ $CERTS_READY -lt $CERTS_TOTAL ]; then
        echo -e "${BLUE}  Note: Certificate issuance can take 2-5 minutes${NC}"
    fi
fi

echo ""
echo "======================================"
echo "8. Test Endpoints (optional)"
echo "======================================"
echo ""
echo "You can test the endpoints with:"
echo ""
echo "  # Test via LoadBalancer IP:"
echo "  curl -k -H 'Host: test-nginx.300510300.xyz' https://192.168.1.100"
echo "  curl -k -H 'Host: test-nginx-another.300510300.xyz' https://192.168.1.100"
echo ""
echo "  # Test via DNS (if configured):"
echo "  curl https://test-nginx.300510300.xyz"
echo "  curl https://test-nginx-another.300510300.xyz"
echo ""
echo "  # Check certificate details:"
echo "  kubectl describe certificate -n nginx-red nginx-red-tls-cert"
echo "  kubectl describe certificate -n nginx-blue nginx-blue-tls-cert"
echo ""

if [ "$FLUX_AVAILABLE" = true ]; then
    echo "Useful FluxCD commands:"
    echo "  flux logs --all-namespaces --follow"
    echo "  flux reconcile kustomization infrastructure --with-source"
    echo "  flux reconcile kustomization applications --with-source"
    echo ""
fi

echo "======================================"
echo "Verification Complete"
echo "======================================"
