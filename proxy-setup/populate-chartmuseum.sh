#!/bin/bash
set -e

# Configuration
CHARTMUSEUM_URL="${CHARTMUSEUM_URL:-http://localhost:8080}"

echo "=========================================="
echo "ChartMuseum Population Script"
echo "=========================================="
echo ""
echo "This script downloads Helm charts from upstream repositories"
echo "and uploads them to your local ChartMuseum instance."
echo ""
echo "ChartMuseum URL: $CHARTMUSEUM_URL"
echo ""

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    echo "ERROR: Helm is not installed"
    echo "Install with: curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
    exit 1
fi

# Check if ChartMuseum is accessible
echo "Checking ChartMuseum connectivity..."
if ! curl -sf "${CHARTMUSEUM_URL}/health" > /dev/null; then
    echo "ERROR: ChartMuseum is not accessible at ${CHARTMUSEUM_URL}"
    echo "Make sure ChartMuseum is running: docker-compose up -d chartmuseum"
    exit 1
fi
echo "ChartMuseum is healthy!"
echo ""

# Create temporary directory for downloads
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

cd "${TEMP_DIR}"

# Define charts to download and upload
# Format: [repo_name]="repo_url|chart_name|version"
declare -A CHARTS=(
    ["ingress-nginx"]="https://kubernetes.github.io/ingress-nginx|ingress-nginx|4.11.3"
    ["jetstack"]="https://charts.jetstack.io|cert-manager|v1.13.6"
)

echo "Charts to be uploaded:"
for chart_name in "${!CHARTS[@]}"; do
    IFS='|' read -r repo_url chart version <<< "${CHARTS[$chart_name]}"
    echo "  - ${chart_name} (${version}) from ${repo_url}"
done
echo ""

# Add repositories
echo "Adding Helm repositories..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jetstack https://charts.jetstack.io
helm repo update
echo ""

# Download and upload each chart
for chart_name in "${!CHARTS[@]}"; do
    IFS='|' read -r repo_url chart version <<< "${CHARTS[$chart_name]}"

    echo "Processing ${chart}:${version}..."

    # Download chart
    echo "  Downloading..."
    helm pull "${chart_name}/${chart}" --version "${version}"

    # Get the downloaded filename
    CHART_FILE="${chart}-${version}.tgz"

    if [ ! -f "${CHART_FILE}" ]; then
        echo "  ERROR: Chart file ${CHART_FILE} not found after download"
        continue
    fi

    # Upload to ChartMuseum
    echo "  Uploading to ChartMuseum..."
    RESPONSE=$(curl -sf --data-binary "@${CHART_FILE}" "${CHARTMUSEUM_URL}/api/charts")

    if [ $? -eq 0 ]; then
        echo "  SUCCESS: ${chart}:${version} uploaded"
    else
        echo "  ERROR: Failed to upload ${chart}:${version}"
    fi

    echo ""
done

# List all charts in ChartMuseum
echo "=========================================="
echo "Charts now available in ChartMuseum:"
echo "=========================================="
curl -s "${CHARTMUSEUM_URL}/api/charts" | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"$//' | sort -u || echo "Unable to list charts"
echo ""

echo "=========================================="
echo "Next Steps:"
echo "=========================================="
echo ""
echo "1. Update FluxCD HelmRepository sources to use ChartMuseum:"
echo "   Edit: infrastructure/sources/helm-repos.yaml"
echo "   Change URLs to: ${CHARTMUSEUM_URL}"
echo ""
echo "2. Commit and push changes to Git repository"
echo ""
echo "3. FluxCD will automatically reconcile and use the local ChartMuseum"
echo ""
echo "To add more chart versions, modify the CHARTS array in this script"
echo "and re-run it."
echo ""
