#!/bin/bash

set -e

echo "======================================"
echo "Create Secrets for FluxCD Deployment"
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
        echo -e "${YELLOW}Using k3s kubectl${NC}"
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

# Verify cluster connectivity
echo "Verifying cluster connectivity..."
if ! $KUBECTL cluster-info &> /dev/null; then
    echo -e "${RED}✗ Cannot connect to cluster${NC}"
    echo "Please ensure k3s is running and KUBECONFIG is set correctly"
    exit 1
fi
echo -e "${GREEN}✓ Connected to cluster${NC}"
echo ""

# Secret 1: Cloudflare API Token
echo "======================================"
echo "Secret 1: Cloudflare API Token"
echo "======================================"
echo ""
echo "This secret is required for cert-manager to perform DNS-01 challenges"
echo "with Let's Encrypt via Cloudflare."
echo ""
echo "To create a Cloudflare API Token:"
echo "  1. Go to https://dash.cloudflare.com/profile/api-tokens"
echo "  2. Click 'Create Token'"
echo "  3. Use 'Edit zone DNS' template or create custom with permissions:"
echo "     - Zone / DNS / Edit"
echo "     - Zone / Zone / Read"
echo "  4. Select your zone: 300510300.xyz"
echo "  5. Copy the generated token"
echo ""

# Check if secret already exists
if $KUBECTL get secret cloudflare-api-token -n cert-manager &> /dev/null; then
    echo -e "${YELLOW}Secret 'cloudflare-api-token' already exists in namespace 'cert-manager'${NC}"
    read -p "Do you want to update it? (yes/no): " -r
    echo ""

    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        $KUBECTL delete secret cloudflare-api-token -n cert-manager
        echo -e "${GREEN}✓ Old secret deleted${NC}"
    else
        echo "Skipping Cloudflare API token creation"
        SKIP_CLOUDFLARE=true
    fi
fi

if [ "$SKIP_CLOUDFLARE" != "true" ]; then
    # Get token from environment or prompt
    if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
        read -sp "Enter your Cloudflare API Token: " CLOUDFLARE_API_TOKEN
        echo ""
    fi

    if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
        echo -e "${RED}✗ Cloudflare API Token is required${NC}"
        exit 1
    fi

    # Create the secret
    $KUBECTL create secret generic cloudflare-api-token \
        --from-literal=api-token="$CLOUDFLARE_API_TOKEN" \
        --namespace=cert-manager

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Secret 'cloudflare-api-token' created in namespace 'cert-manager'${NC}"
    else
        echo -e "${RED}✗ Failed to create secret${NC}"
        exit 1
    fi
fi

echo ""
echo "======================================"
echo "Summary of Created Secrets"
echo "======================================"
echo ""

echo "Secrets in cert-manager namespace:"
$KUBECTL get secrets -n cert-manager | grep -E "NAME|cloudflare"

echo ""
echo -e "${GREEN}======================================"
echo "✓ Secrets Configuration Complete!"
echo "======================================${NC}"
echo ""
echo "Next steps:"
echo "  1. Verify secrets are correctly configured:"
echo "     kubectl get secrets -n cert-manager"
echo "  2. Push your manifests to GitHub to trigger deployment"
echo "  3. Monitor deployment with ./verify-deployment.sh"
echo ""
echo "Notes:"
echo "  - Secrets are NOT stored in Git (manual creation required)"
echo "  - After cluster reset, re-run this script to recreate secrets"
echo "  - For production, consider using SOPS, Sealed Secrets, or External Secrets Operator"
echo ""
