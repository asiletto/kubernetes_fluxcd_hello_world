#!/bin/bash
set -e

# Configuration
REGISTRY_HOST="${REGISTRY_HOST:-localhost}"
REGISTRY_PORT="${REGISTRY_PORT:-5000}"

echo "=========================================="
echo "K3s Registry Mirrors Setup"
echo "=========================================="
echo ""
echo "This script configures K3s to use a local Docker Registry as a pull-through cache."
echo ""
echo "Registry configuration:"
echo "  Host: $REGISTRY_HOST"
echo "  Port: $REGISTRY_PORT"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root (or with sudo)"
    echo "Usage: sudo ./setup-registry-mirrors.sh"
    exit 1
fi

# Check if K3s is installed
if ! command -v k3s &> /dev/null; then
    echo "ERROR: K3s is not installed on this system"
    exit 1
fi

# Create K3s config directory if it doesn't exist
mkdir -p /etc/rancher/k3s

# Generate registries.yaml
echo "Generating /etc/rancher/k3s/registries.yaml..."

cat > /etc/rancher/k3s/registries.yaml <<EOF
mirrors:
  docker.io:
    endpoint:
      - "http://${REGISTRY_HOST}:${REGISTRY_PORT}"
  ghcr.io:
    endpoint:
      - "http://${REGISTRY_HOST}:${REGISTRY_PORT}"
  registry.k8s.io:
    endpoint:
      - "http://${REGISTRY_HOST}:${REGISTRY_PORT}"
  quay.io:
    endpoint:
      - "http://${REGISTRY_HOST}:${REGISTRY_PORT}"

# Uncomment if your registry requires authentication
# configs:
#   "${REGISTRY_HOST}:${REGISTRY_PORT}":
#     auth:
#       username: admin
#       password: password
EOF

echo "Configuration file created successfully!"
echo ""
echo "Content of /etc/rancher/k3s/registries.yaml:"
echo "----------------------------------------"
cat /etc/rancher/k3s/registries.yaml
echo "----------------------------------------"
echo ""

# Ask for confirmation before restarting K3s
read -p "Restart K3s service to apply changes? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Restarting K3s..."
    systemctl restart k3s
    echo "K3s restarted successfully!"
    echo ""
    echo "Waiting for K3s to be ready..."
    sleep 5

    # Check K3s status
    if systemctl is-active --quiet k3s; then
        echo "K3s is running!"
        echo ""
        echo "You can verify the configuration by pulling an image:"
        echo "  sudo k3s crictl pull nginx:1.27-alpine"
        echo ""
        echo "Check Docker Registry logs to confirm the pull-through cache is working."
    else
        echo "WARNING: K3s failed to start. Check logs with: journalctl -u k3s -f"
        exit 1
    fi
else
    echo "K3s restart skipped. Changes will not take effect until you restart K3s manually:"
    echo "  sudo systemctl restart k3s"
fi

echo ""
echo "Setup complete!"
