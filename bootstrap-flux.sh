#!/bin/bash

set -e

echo "======================================"
echo "FluxCD Bootstrap Script"
echo "======================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
GITHUB_USER="${GITHUB_USER:-}"
GITHUB_REPO="${GITHUB_REPO:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
CLUSTER_NAME="k3s-local"
FLUX_NAMESPACE="flux-system"

# Step 1: Verify prerequisites
echo "Step 1: Verifying prerequisites..."

# Check if flux CLI is installed
if ! command -v flux &> /dev/null; then
    echo -e "${RED}✗ flux CLI not found${NC}"
    echo ""
    echo "Please install flux CLI first:"
    echo "  curl -s https://fluxcd.io/install.sh | sudo bash"
    echo ""
    exit 1
fi
echo -e "${GREEN}✓ flux CLI installed: $(flux --version | head -n 1)${NC}"

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
    echo -e "${GREEN}✓ kubectl installed${NC}"
fi

# Set KUBECONFIG
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

# Check cluster connectivity
echo ""
echo "Checking cluster connectivity..."
if ! $KUBECTL cluster-info &> /dev/null; then
    echo -e "${RED}✗ Cannot connect to cluster${NC}"
    echo "Please ensure k3s is running and KUBECONFIG is set correctly"
    exit 1
fi
echo -e "${GREEN}✓ Connected to cluster${NC}"

# Step 2: Get GitHub configuration
echo ""
echo "Step 2: GitHub Configuration"
echo "=============================="

if [ -z "$GITHUB_USER" ]; then
    read -p "Enter your GitHub username: " GITHUB_USER
fi

if [ -z "$GITHUB_REPO" ]; then
    read -p "Enter your GitHub repository name (e.g., 02_flux_github): " GITHUB_REPO
fi

if [ -z "$GITHUB_TOKEN" ]; then
    echo ""
    echo -e "${YELLOW}GitHub Personal Access Token required${NC}"
    echo "The token needs the following permissions:"
    echo "  - repo (full access)"
    echo ""
    echo "Create one at: https://github.com/settings/tokens/new"
    echo ""
    read -sp "Enter your GitHub personal access token: " GITHUB_TOKEN
    echo ""
fi

export GITHUB_TOKEN

# Step 3: Pre-flight checks
echo ""
echo "Step 3: Running pre-flight checks..."
flux check --pre

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Pre-flight checks failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Pre-flight checks passed${NC}"

# Step 4: Bootstrap FluxCD
echo ""
echo "Step 4: Bootstrapping FluxCD..."
echo ""
echo "Configuration:"
echo "  GitHub User:  $GITHUB_USER"
echo "  GitHub Repo:  $GITHUB_REPO"
echo "  Cluster:      $CLUSTER_NAME"
echo "  Branch:       main"
echo "  Path:         ./clusters/$CLUSTER_NAME"
echo ""
read -p "Proceed with bootstrap? (yes/no): " -r
echo ""

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Aborted."
    exit 0
fi

flux bootstrap github \
  --owner="$GITHUB_USER" \
  --repository="$GITHUB_REPO" \
  --branch=main \
  --path="./clusters/$CLUSTER_NAME" \
  --personal \
  --token-auth

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Bootstrap failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✓ FluxCD bootstrapped successfully${NC}"

# Step 5: Wait for FluxCD to be ready
echo ""
echo "Step 5: Waiting for FluxCD to be ready..."
echo "This may take a few minutes..."

timeout=300
while [ $timeout -gt 0 ]; do
    if flux check &> /dev/null; then
        echo -e "${GREEN}✓ FluxCD is ready${NC}"
        break
    fi
    sleep 5
    ((timeout-=5))
    echo -n "."
done

if [ $timeout -le 0 ]; then
    echo ""
    echo -e "${YELLOW}Warning: Timeout waiting for FluxCD to be fully ready${NC}"
    echo "You can check status manually with: flux check"
fi

# Step 6: Verify installation
echo ""
echo "Step 6: Verifying installation..."
echo ""

echo "FluxCD Components:"
$KUBECTL get pods -n flux-system

echo ""
echo "GitRepository:"
flux get sources git

echo ""
echo "Kustomizations:"
flux get kustomizations

echo ""
echo -e "${GREEN}======================================"
echo "✓ FluxCD Bootstrap Complete!"
echo "======================================${NC}"
echo ""
echo "Next steps:"
echo "  1. Run ./create-secrets.sh to create required secrets"
echo "  2. Commit and push your manifests to trigger reconciliation"
echo "  3. Monitor with: flux get kustomizations --watch"
echo "  4. Check logs with: flux logs --all-namespaces --follow"
echo ""
echo "Useful commands:"
echo "  flux reconcile kustomization flux-system --with-source"
echo "  flux get all"
echo "  kubectl get helmreleases -A"
echo ""
