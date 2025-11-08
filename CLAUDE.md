# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a production-ready GitOps repository using FluxCD to manage K3s cluster deployments. The repository follows a declarative GitOps approach where all cluster state is defined in Git, and FluxCD automatically reconciles the cluster to match the desired state.

## Architecture

### Three-Tier Dependency Model

The deployment follows a strict dependency chain with three separate Flux Kustomizations:

1. **Infrastructure** (`clusters/k3s-local/infrastructure.yaml`)
   - Deploys core infrastructure: NGINX Ingress Controller and cert-manager
   - Includes health checks to ensure all deployments are ready before proceeding
   - Path: `./infrastructure`

2. **Infrastructure-Config** (`clusters/k3s-local/infrastructure-config.yaml`)
   - Depends on Infrastructure
   - Deploys ClusterIssuers for Let's Encrypt (staging and production)
   - Must wait for cert-manager to be fully operational
   - Path: `./infrastructure/cert-manager-config`

3. **Applications** (`clusters/k3s-local/applications.yaml`)
   - Depends on both Infrastructure and Infrastructure-Config
   - Deploys application workloads (nginx-red, nginx-blue)
   - Path: `./apps`

**Critical**: This dependency chain ensures cert-manager is ready before ClusterIssuers are created, and ClusterIssuers exist before applications request TLS certificates.

### Certificate Management

- Uses DNS-01 challenge via Cloudflare (required for private IP addresses)
- Two ClusterIssuers available:
  - `letsencrypt-staging`: For testing (untrusted certificates, no rate limits)
  - `letsencrypt-prod`: For production (trusted certificates, 50/week rate limit)
- Cloudflare API token stored as secret `cloudflare-api-token` in `cert-manager` namespace
- Applications reference ClusterIssuer via annotation: `cert-manager.io/cluster-issuer: "letsencrypt-prod"`

### Directory Structure Logic

```
clusters/k3s-local/        # Cluster-specific Flux Kustomizations (what to deploy)
infrastructure/            # Infrastructure component manifests (what gets deployed)
├── sources/              # Helm repositories
├── namespaces/           # All namespace definitions
├── nginx-ingress/        # NGINX Ingress HelmRelease
├── cert-manager/         # cert-manager HelmRelease
└── cert-manager-config/  # ClusterIssuers (separate to ensure cert-manager is ready)
apps/                      # Application manifests (nginx-red, nginx-blue)
```

## Common Commands

### FluxCD Operations

```bash
# Check FluxCD health
flux check

# View all Kustomizations status
flux get kustomizations

# Force reconciliation (after git push)
flux reconcile kustomization flux-system --with-source
flux reconcile kustomization infrastructure --with-source
flux reconcile kustomization infrastructure-config --with-source
flux reconcile kustomization applications --with-source

# View logs
flux logs --all-namespaces --follow
flux logs --level=error

# Suspend/Resume automatic reconciliation
flux suspend kustomization applications
flux resume kustomization applications
```

### Certificate Management

```bash
# Check certificate status
kubectl get certificates -A
kubectl describe certificate nginx-red-tls-cert -n nginx-red

# View certificate requests and challenges
kubectl get certificaterequests -A
kubectl describe challenge -A

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager -f

# Verify Cloudflare secret exists
kubectl get secret cloudflare-api-token -n cert-manager
```

### Deployment Scripts

```bash
# Clean install k3s
./reset-k3s.sh

# Bootstrap FluxCD (requires GITHUB_USER, GITHUB_REPO, GITHUB_TOKEN)
./bootstrap-flux.sh

# Create required secrets (requires CLOUDFLARE_API_TOKEN)
./create-secrets.sh

# Verify deployment status
./verify-deployment.sh
```

### Kubernetes Operations

```bash
# View HelmReleases
flux get helmreleases -A
kubectl describe helmrelease ingress-nginx -n ingress-nginx

# Check pod status
kubectl get pods -A
kubectl logs -n nginx-red deployment/nginx-red

# Check ingress resources
kubectl get ingress -A
kubectl describe ingress nginx-red-ingress -n nginx-red
```

## Making Changes

### Deployment Workflow

1. Modify manifests in local repository
2. Commit: `git commit -am "Description"`
3. Push: `git push origin main`
4. FluxCD automatically detects changes (polls every 1m)
5. Monitor: `flux get kustomizations --watch`

Or force immediate reconciliation:
```bash
flux reconcile kustomization <name> --with-source
```

### Adding New Applications

When adding applications that need TLS:

1. Create application namespace in `infrastructure/namespaces/namespaces.yaml`
2. Add application manifests under `apps/<app-name>/`
3. In Ingress, use annotation: `cert-manager.io/cluster-issuer: "letsencrypt-prod"`
4. Include in `apps/kustomization.yaml`
5. Add health check in `clusters/k3s-local/applications.yaml` if desired

### Modifying Infrastructure

When changing HelmReleases or infrastructure components:

- Understand that changes trigger reconciliation cascade due to dependencies
- Applications will be reconciled after infrastructure changes complete
- Health checks in `infrastructure.yaml` prevent premature application deployment

## Important Configuration Details

### NGINX Ingress LoadBalancer

- External IP: `192.168.1.100` (configured via k3s ServiceLB)
- All ingress traffic routes through this IP
- DNS records must point to this IP

### Secret Management

Secrets are **NOT** stored in Git and must be manually created:

- `cloudflare-api-token` in `cert-manager` namespace (required for DNS-01 challenges)
- Use `./create-secrets.sh` script after cluster reset

### FluxCD Reconciliation

- Default interval: 10 minutes
- Retry interval: 1 minute
- Timeout: 5 minutes
- All Kustomizations have `wait: true` to ensure ordered deployment

### DNS Configuration

Applications use DNS zone: `300510300.xyz`
- DNS-01 challenges require DNS records to be pre-configured in Cloudflare
- Current apps: `test-nginx.300510300.xyz`, `test-nginx-another.300510300.xyz`

## Local Repository Proxies (Optional)

This repository can be configured to use local Docker Registry and ChartMuseum proxies instead of pulling directly from upstream registries. This is useful for:

- Reducing external bandwidth usage
- Improving image pull performance
- Working in air-gapped or restricted network environments
- Caching frequently used images and charts

### Architecture

The proxy setup uses two external Docker containers:

1. **Docker Registry** (port 5000): Pull-through cache for container images
   - Automatically caches images from docker.io, ghcr.io, registry.k8s.io, quay.io
   - Transparent to applications - no manifest changes needed
   - Configured via K3s registry mirrors

2. **ChartMuseum** (port 8080): Repository for Helm charts
   - Requires manual population of charts (not automatic proxying)
   - FluxCD HelmRepository sources point to ChartMuseum instead of upstream
   - Charts must be uploaded before use

### Setup Instructions

#### 1. Deploy Docker Registry and ChartMuseum

```bash
# Navigate to proxy setup directory
cd proxy-setup/

# Start containers
docker-compose up -d

# Verify they're running
docker-compose ps
docker-compose logs -f

# Test connectivity
curl http://localhost:5000/v2/_catalog  # Docker Registry
curl http://localhost:8080/health        # ChartMuseum
```

#### 2. Populate ChartMuseum with Required Helm Charts

```bash
# Run the population script
./populate-chartmuseum.sh

# Or specify custom ChartMuseum URL
CHARTMUSEUM_URL=http://192.168.1.50:8080 ./populate-chartmuseum.sh
```

This script downloads and uploads:
- ingress-nginx chart (version 4.11.3)
- cert-manager chart (version 1.13.7)

To add more charts or versions, edit the `CHARTS` array in `populate-chartmuseum.sh`.

#### 3. Configure K3s Registry Mirrors

On each K3s node, configure registry mirrors to use the Docker Registry:

```bash
# Update REGISTRY_HOST with your Docker host IP
sudo REGISTRY_HOST=192.168.1.50 ./setup-registry-mirrors.sh

# Or manually create /etc/rancher/k3s/registries.yaml
# See registries.yaml.template for format
```

This configures K3s to pull all images through your local Docker Registry cache.

**Important**: Use the IP address of the Docker host, not `localhost` (K3s nodes need to reach the registry from inside containers).

#### 4. Update FluxCD HelmRepository Sources

Edit `infrastructure/sources/helm-repos.yaml` and replace `CHARTMUSEUM_HOST` placeholder:

```bash
# Replace CHARTMUSEUM_HOST with your actual IP/hostname
sed -i 's/CHARTMUSEUM_HOST/192.168.1.50/g' infrastructure/sources/helm-repos.yaml
```

Or manually update the URLs to point to your ChartMuseum instance.

#### 5. Commit and Deploy

```bash
# Commit changes
git add infrastructure/sources/helm-repos.yaml
git commit -m "Configure ChartMuseum as Helm repository proxy"
git push origin main

# Force reconciliation
flux reconcile kustomization flux-system --with-source
flux reconcile kustomization infrastructure --with-source
```

### Verification

```bash
# Verify registry mirrors are configured
sudo cat /etc/rancher/k3s/registries.yaml

# Test image pull through registry cache
sudo k3s crictl pull nginx:1.27-alpine
# Check Docker Registry logs for cache hit
docker logs docker-registry

# Verify FluxCD can reach ChartMuseum
flux get sources helm -A
# Should show HelmRepository sources as Ready

# Test Helm chart availability
curl http://192.168.1.50:8080/api/charts | grep -o '"name":"[^"]*"'
```

### Maintenance

#### Adding New Chart Versions

When HelmRelease versions are updated:

```bash
# Download new chart version
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm pull ingress-nginx/ingress-nginx --version 4.12.0

# Upload to ChartMuseum
curl --data-binary "@ingress-nginx-4.12.0.tgz" http://192.168.1.50:8080/api/charts

# Verify upload
curl http://192.168.1.50:8080/api/charts/ingress-nginx
```

#### Clearing Docker Registry Cache

```bash
# Registry cache is stored in Docker volume
docker-compose down
docker volume rm proxy-setup_registry-data
docker-compose up -d
```

#### Monitoring

```bash
# Check proxy container status
docker-compose ps

# View logs
docker-compose logs -f docker-registry
docker-compose logs -f chartmuseum

# Check disk usage
docker system df -v
```

### Reverting to Upstream Sources

To revert to pulling directly from upstream:

1. **Helm Charts**: Uncomment original URLs in `infrastructure/sources/helm-repos.yaml`
2. **Container Images**: Remove `/etc/rancher/k3s/registries.yaml` and restart K3s
3. Commit and push changes to Git

### Troubleshooting Proxy Issues

#### HelmRepository Not Ready

```bash
# Check FluxCD can reach ChartMuseum
flux get sources helm -A
kubectl describe helmrepository <name> -n flux-system

# Common issues:
# - ChartMuseum not running: docker-compose ps
# - Wrong URL in helm-repos.yaml
# - Charts not uploaded: curl http://<chartmuseum>:8080/api/charts
```

#### Images Not Pulling Through Registry

```bash
# Verify K3s registry configuration
sudo cat /etc/rancher/k3s/registries.yaml

# Check K3s is using the mirror
sudo journalctl -u k3s -f | grep registry

# Test registry connectivity from K3s node
curl http://<registry-host>:5000/v2/_catalog

# Common issues:
# - Wrong IP in registries.yaml (should be Docker host IP, not localhost)
# - K3s not restarted after config change
# - Docker Registry container not running
```

#### Chart Version Not Found

```bash
# List available charts in ChartMuseum
curl http://<chartmuseum>:8080/api/charts

# Check if required version is uploaded
curl http://<chartmuseum>:8080/api/charts/<chart-name>

# Re-run population script with updated versions
./populate-chartmuseum.sh
```

## Troubleshooting

### Certificates Not Ready

1. Check ClusterIssuer exists: `kubectl get clusterissuer`
2. Verify Cloudflare secret: `kubectl get secret cloudflare-api-token -n cert-manager`
3. Check challenge status: `kubectl describe challenge -A`
4. Review cert-manager logs: `kubectl logs -n cert-manager deployment/cert-manager -f`

### Kustomization Failing

1. Check dependencies are healthy: `flux get kustomizations`
2. Verify GitRepository source: `flux get sources git`
3. View detailed status: `kubectl describe kustomization <name> -n flux-system`
4. Check for validation errors: `flux logs --level=error`

### HelmRelease Issues

1. Check status: `flux get helmreleases -A`
2. View events: `kubectl describe helmrelease <name> -n <namespace>`
3. Verify Helm repository accessible: `flux get sources helm`
4. Check controller logs: `kubectl logs -n flux-system deployment/helm-controller -f`
