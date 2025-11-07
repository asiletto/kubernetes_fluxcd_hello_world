#!/bin/bash

set -e

echo "======================================"
echo "K3s Complete Reset and Reinstallation"
echo "======================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
K3S_VERSION="${K3S_VERSION:-}"  # Leave empty for latest
DISABLE_TRAEFIK="--disable traefik"
KUBECONFIG_MODE="--write-kubeconfig-mode 644"

echo -e "${YELLOW}WARNING: This will completely remove k3s and all its data!${NC}"
echo "This includes:"
echo "  - All pods, services, deployments"
echo "  - All persistent volumes and data"
echo "  - All configurations"
echo ""
read -p "Are you sure you want to continue? (yes/no): " -r
echo ""

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Step 1: Uninstall k3s if present
echo "Step 1: Checking for existing k3s installation..."
if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
    echo -e "${YELLOW}Found existing k3s installation. Uninstalling...${NC}"
    sudo /usr/local/bin/k3s-uninstall.sh
    echo -e "${GREEN}✓ k3s uninstalled${NC}"
else
    echo "No existing k3s installation found."
fi

# Step 2: Clean up residual files and directories
echo ""
echo "Step 2: Cleaning up residual files..."
sudo rm -rf /etc/rancher
sudo rm -rf /var/lib/rancher
sudo rm -rf /var/lib/kubelet
sudo rm -rf ~/.kube
echo -e "${GREEN}✓ Residual files cleaned${NC}"

# Step 3: Install k3s
echo ""
echo "Step 3: Installing k3s..."
echo "Configuration:"
echo "  - Traefik: disabled"
echo "  - Kubeconfig mode: 644"
if [ -n "$K3S_VERSION" ]; then
    echo "  - Version: $K3S_VERSION"
    curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$K3S_VERSION" sh -s - $DISABLE_TRAEFIK $KUBECONFIG_MODE
else
    echo "  - Version: latest"
    curl -sfL https://get.k3s.io | sh -s - $DISABLE_TRAEFIK $KUBECONFIG_MODE
fi

echo -e "${GREEN}✓ k3s installed${NC}"

# Step 4: Wait for k3s to be ready
echo ""
echo "Step 4: Waiting for k3s to be ready..."
sleep 5

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${YELLOW}kubectl not found, using k3s kubectl${NC}"
    KUBECTL="sudo k3s kubectl"
else
    KUBECTL="kubectl"
fi

# Set KUBECONFIG
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Wait for node to be ready
echo "Waiting for node to be ready (timeout: 60s)..."
timeout=60
while [ $timeout -gt 0 ]; do
    if sudo $KUBECTL get nodes 2>/dev/null | grep -q "Ready"; then
        echo -e "${GREEN}✓ Node is ready${NC}"
        break
    fi
    sleep 2
    ((timeout-=2))
done

if [ $timeout -le 0 ]; then
    echo -e "${RED}✗ Timeout waiting for node to be ready${NC}"
    exit 1
fi

# Step 5: Verify cluster
echo ""
echo "Step 5: Verifying cluster..."
echo ""
echo "Cluster Info:"
sudo $KUBECTL cluster-info

echo ""
echo "Nodes:"
sudo $KUBECTL get nodes -o wide

echo ""
echo "System Pods:"
sudo $KUBECTL get pods -n kube-system

echo ""
echo -e "${GREEN}======================================"
echo "✓ K3s successfully reset and installed"
echo "======================================${NC}"
echo ""
echo "Next steps:"
echo "  1. Configure your secrets (Cloudflare API token, etc.)"
echo "  2. Run ./bootstrap-flux.sh to install FluxCD"
echo "  3. Push your manifests to GitHub"
echo ""
echo "KUBECONFIG is available at: /etc/rancher/k3s/k3s.yaml"
echo ""
