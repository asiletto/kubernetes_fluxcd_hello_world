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
