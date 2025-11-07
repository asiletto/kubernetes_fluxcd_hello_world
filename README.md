# FluxCD GitOps Deployment for K3s

This repository contains a production-ready GitOps setup using FluxCD for deploying applications on K3s, with clear separation between infrastructure and application components.

## Architecture Overview

### Repository Structure

```
.
├── clusters/
│   └── k3s-local/                    # Cluster-specific configuration
│       ├── flux-system/              # FluxCD bootstrap (auto-generated)
│       ├── infrastructure.yaml       # Infrastructure Kustomization
│       └── applications.yaml         # Applications Kustomization (depends on infra)
│
├── infrastructure/                   # Infrastructure components
│   ├── sources/
│   │   ├── helm-repos.yaml          # Helm repository sources
│   │   └── kustomization.yaml
│   ├── namespaces/
│   │   ├── namespaces.yaml          # All namespaces
│   │   └── kustomization.yaml
│   ├── nginx-ingress/
│   │   ├── release.yaml             # NGINX Ingress HelmRelease
│   │   └── kustomization.yaml
│   ├── cert-manager/
│   │   ├── release.yaml             # cert-manager HelmRelease
│   │   ├── issuers.yaml             # Let's Encrypt ClusterIssuers
│   │   └── kustomization.yaml
│   └── kustomization.yaml           # Main infrastructure kustomization
│
├── apps/                            # Application components
│   ├── nginx-red/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── configmap.yaml
│   │   ├── ingress.yaml
│   │   └── kustomization.yaml
│   ├── nginx-blue/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── configmap.yaml
│   │   ├── ingress.yaml
│   │   └── kustomization.yaml
│   └── kustomization.yaml
│
├── reset-k3s.sh                     # Clean and reinstall k3s
├── bootstrap-flux.sh                # Bootstrap FluxCD
├── create-secrets.sh                # Create required secrets
├── verify-deployment.sh             # Verify deployment status
└── README-FLUXCD.md                 # This file
```

### Component Separation

#### Infrastructure Components
- **NGINX Ingress Controller**: Manages HTTP/HTTPS traffic routing
- **cert-manager**: Automates TLS certificate provisioning via Let's Encrypt
- **ClusterIssuers**: Let's Encrypt staging and production issuers
- Deployed in dedicated namespaces: `ingress-nginx`, `cert-manager`

#### Application Components
- **nginx-red**: Demo application with red background
- **nginx-blue**: Demo application with blue background
- Each application deployed in its own namespace
- Each application has its own Ingress resource with TLS

## Prerequisites

### Required Tools
- **k3s**: Lightweight Kubernetes (or fresh install via `reset-k3s.sh`)
- **flux CLI**: FluxCD command-line tool
  ```bash
  curl -s https://fluxcd.io/install.sh | sudo bash
  ```
- **kubectl**: Kubernetes CLI (included with k3s)
- **git**: Version control

### Required Accounts & Tokens
1. **GitHub Account**: For repository hosting
2. **GitHub Personal Access Token**:
   - Create at: https://github.com/settings/tokens/new
   - Required permissions: `repo` (full access)
3. **Cloudflare Account**: For DNS management
4. **Cloudflare API Token**:
   - Create at: https://dash.cloudflare.com/profile/api-tokens
   - Template: "Edit zone DNS"
   - Permissions:
     - Zone / DNS / Edit
     - Zone / Zone / Read
   - Zone: `300510300.xyz`

### DNS Configuration
Ensure the following DNS records are configured in Cloudflare:

```
test-nginx.300510300.xyz         A    192.168.1.100
test-nginx-another.300510300.xyz A    192.168.1.100
```

## Quick Start Guide

### Step 1: Reset K3s (Optional)

If you want to start with a clean cluster:

```bash
./reset-k3s.sh
```

This will:
- Uninstall existing k3s
- Clean up all residual files
- Reinstall k3s with correct configuration
- Verify cluster is ready

### Step 2: Bootstrap FluxCD

```bash
export GITHUB_USER="your-github-username"
export GITHUB_REPO="02_flux_github"
export GITHUB_TOKEN="ghp_xxxxxxxxxxxxx"

./bootstrap-flux.sh
```

This will:
- Verify prerequisites
- Run FluxCD pre-flight checks
- Bootstrap FluxCD to the cluster
- Configure GitRepository source
- Deploy initial Kustomizations

### Step 3: Create Secrets

```bash
export CLOUDFLARE_API_TOKEN="your-cloudflare-api-token"

./create-secrets.sh
```

This creates:
- `cloudflare-api-token` secret in `cert-manager` namespace

**Important**: Secrets are NOT stored in Git and must be recreated after cluster resets.

### Step 4: Commit and Push

```bash
git add .
git commit -m "Initial FluxCD setup"
git push origin main
```

FluxCD will automatically:
1. Detect the push
2. Reconcile infrastructure components
3. Wait for infrastructure to be healthy
4. Deploy application components
5. Request TLS certificates from Let's Encrypt

### Step 5: Verify Deployment

```bash
./verify-deployment.sh
```

Or monitor in real-time:

```bash
flux get kustomizations --watch
```

## Deployment Workflow

### How GitOps Works

```
Developer                  GitHub                    FluxCD                   K8s Cluster
    |                         |                         |                          |
    |-- git push ------------>|                         |                          |
    |                         |                         |                          |
    |                         |<-- poll (every 1m) -----|                          |
    |                         |                         |                          |
    |                         |--- changes detected --->|                          |
    |                         |                         |                          |
    |                         |                         |-- reconcile ------------>|
    |                         |                         |                          |
    |                         |                         |<-- status --------------|
    |                         |                         |                          |
    |                         |<-- commit status -------|                          |
```

### Dependency Chain

```
Infrastructure Kustomization
  ├── Namespaces (created first)
  ├── Helm Repositories
  ├── NGINX Ingress Controller (HelmRelease)
  │   └── Wait for deployment to be ready
  └── cert-manager (HelmRelease)
      ├── Wait for deployment to be ready
      └── ClusterIssuers (created after cert-manager is ready)

Applications Kustomization (depends on Infrastructure)
  ├── nginx-red
  │   ├── ConfigMap
  │   ├── Deployment
  │   ├── Service
  │   └── Ingress (triggers certificate request)
  └── nginx-blue
      ├── ConfigMap
      ├── Deployment
      ├── Service
      └── Ingress (triggers certificate request)
```

## Configuration Details

### Infrastructure Configuration

#### NGINX Ingress Controller
- **Version**: 4.11.x (app version 1.11.1)
- **Service Type**: LoadBalancer (k3s ServiceLB)
- **External IP**: 192.168.1.100
- **Ports**: 80 (HTTP), 443 (HTTPS)
- **Security**: Snippet annotations disabled, non-root, read-only root filesystem

#### cert-manager
- **Version**: 1.13.x
- **CRDs**: Installed and managed by Helm
- **Challenge Type**: DNS-01 (via Cloudflare)
- **Issuers**:
  - `letsencrypt-staging`: For testing (untrusted certificates)
  - `letsencrypt-prod`: For production (trusted certificates)

### Application Configuration

#### nginx-red
- **Namespace**: `nginx-red`
- **Replicas**: 2
- **Image**: `nginx:1.27-alpine`
- **Hostname**: `test-nginx.300510300.xyz`
- **Background**: Red (#dc2626)

#### nginx-blue
- **Namespace**: `nginx-blue`
- **Replicas**: 2
- **Image**: `nginx:1.27-alpine`
- **Hostname**: `test-nginx-another.300510300.xyz`
- **Background**: Blue (#2563eb)

## Managing the Deployment

### Common Operations

#### Force Reconciliation

```bash
# Reconcile everything
flux reconcile kustomization flux-system --with-source

# Reconcile infrastructure only
flux reconcile kustomization infrastructure --with-source

# Reconcile applications only
flux reconcile kustomization applications --with-source
```

#### View Logs

```bash
# All FluxCD logs
flux logs --all-namespaces --follow

# Specific component
kubectl logs -n flux-system deployment/source-controller -f
```

#### Check Resource Status

```bash
# FluxCD resources
flux get all

# Helm releases
kubectl get helmreleases -A

# Certificates
kubectl get certificates -A
kubectl describe certificate -n nginx-red nginx-red-tls-cert
```

#### Suspend/Resume Reconciliation

```bash
# Suspend (stop automatic updates)
flux suspend kustomization applications

# Resume
flux resume kustomization applications
```

### Making Changes

1. **Edit manifests** in your local repository
2. **Commit changes**: `git commit -am "Description of changes"`
3. **Push to GitHub**: `git push origin main`
4. **Wait for reconciliation** (automatic, every 1m) or force:
   ```bash
   flux reconcile kustomization applications --with-source
   ```

### Rolling Back Changes

```bash
# Revert git commit
git revert HEAD
git push origin main

# Or force reconcile to a specific commit
flux reconcile kustomization applications --with-source
```

## Troubleshooting

### FluxCD Issues

```bash
# Check FluxCD health
flux check

# View reconciliation status
flux get kustomizations

# View source status
flux get sources git

# Check for errors
flux logs --level=error
```

### Infrastructure Issues

```bash
# Check Helm releases
flux get helmreleases -A

# View HelmRelease details
kubectl describe helmrelease ingress-nginx -n ingress-nginx

# Check pod status
kubectl get pods -n ingress-nginx
kubectl get pods -n cert-manager
```

### Certificate Issues

```bash
# Check certificate status
kubectl get certificates -A
kubectl describe certificate nginx-red-tls-cert -n nginx-red

# Check certificate requests
kubectl get certificaterequests -A

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager -f

# Verify Cloudflare secret
kubectl get secret cloudflare-api-token -n cert-manager
kubectl describe secret cloudflare-api-token -n cert-manager
```

### Application Issues

```bash
# Check pod logs
kubectl logs -n nginx-red deployment/nginx-red
kubectl logs -n nginx-blue deployment/nginx-blue

# Check ingress status
kubectl get ingress -A
kubectl describe ingress nginx-red-ingress -n nginx-red

# Test connectivity
curl -k -H 'Host: test-nginx.300510300.xyz' https://192.168.1.100
```

### Common Problems

#### Certificates Not Ready
- **Symptom**: Certificate status shows "False"
- **Cause**: DNS-01 challenge failing
- **Solutions**:
  1. Verify Cloudflare API token is correct
  2. Check DNS records are configured
  3. View challenge details: `kubectl describe challenge -A`
  4. Check cert-manager logs

#### HelmRelease Failed
- **Symptom**: `flux get helmreleases` shows "False"
- **Cause**: Helm chart installation/upgrade failed
- **Solutions**:
  1. Check HelmRelease events: `kubectl describe helmrelease <name> -n <namespace>`
  2. Verify Helm repository is accessible: `flux get sources helm`
  3. Check pod logs for the failed component

#### Kustomization Not Reconciling
- **Symptom**: Changes not applied
- **Cause**: Source or dependency issues
- **Solutions**:
  1. Check GitRepository source: `flux get sources git`
  2. Verify dependencies are healthy: `flux get kustomizations`
  3. Force reconciliation: `flux reconcile kustomization <name> --with-source`

## Testing

### Test HTTP → HTTPS Redirect

```bash
curl -I -H 'Host: test-nginx.300510300.xyz' http://192.168.1.100
# Should return 308 Permanent Redirect to https://
```

### Test HTTPS Endpoints

```bash
# Via LoadBalancer IP
curl -H 'Host: test-nginx.300510300.xyz' https://192.168.1.100
curl -H 'Host: test-nginx-another.300510300.xyz' https://192.168.1.100

# Via DNS (if configured)
curl https://test-nginx.300510300.xyz
curl https://test-nginx-another.300510300.xyz
```

### Verify Certificate

```bash
echo | openssl s_client -servername test-nginx.300510300.xyz -connect 192.168.1.100:443 2>/dev/null | openssl x509 -noout -text
```

## Cleanup

### Remove Applications Only

```bash
flux delete kustomization applications --silent
kubectl delete namespace nginx-red nginx-blue
```

### Remove Infrastructure

```bash
flux delete kustomization infrastructure --silent
kubectl delete namespace ingress-nginx cert-manager
```

### Full Cleanup (including FluxCD)

```bash
flux uninstall --silent
```

### Complete Cluster Reset

```bash
./reset-k3s.sh
```

## Security Considerations

### Secrets Management

Current setup uses **manual secrets** (not stored in Git). For production, consider:

- **Sealed Secrets**: Encrypt secrets in Git
- **SOPS**: Encrypt YAML files with age/GPG
- **External Secrets Operator**: Sync from external secret stores (Vault, AWS Secrets Manager)

### Network Policies

Consider adding NetworkPolicies to restrict traffic between namespaces:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-from-other-namespaces
  namespace: nginx-red
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector: {}
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
```

### Image Security

Consider adding:
- **Image scanning**: Scan images for vulnerabilities
- **Image signing**: Verify image signatures
- **Image policies**: Restrict which images can be deployed

## Future Enhancements

### Monitoring & Observability

Add Prometheus and Grafana for monitoring:

```
infrastructure/
└── monitoring/
    ├── prometheus/
    ├── grafana/
    └── kustomization.yaml
```

### Multi-Environment

Extend to multiple environments:

```
clusters/
├── k3s-dev/
├── k3s-staging/
└── k3s-prod/
```

### Automated Image Updates

Enable Flux ImageRepository and ImagePolicy for automatic updates:

```yaml
apiVersion: image.toolkit.fluxcd.io/v1beta1
kind: ImageRepository
metadata:
  name: nginx
spec:
  image: nginx
  interval: 5m

apiVersion: image.toolkit.fluxcd.io/v1beta1
kind: ImagePolicy
metadata:
  name: nginx-alpine
spec:
  imageRepositoryRef:
    name: nginx
  policy:
    semver:
      range: 1.27.x
```

## References

- [FluxCD Documentation](https://fluxcd.io/docs/)
- [K3s Documentation](https://docs.k3s.io/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [NGINX Ingress Controller Documentation](https://kubernetes.github.io/ingress-nginx/)
- [Kustomize Documentation](https://kustomize.io/)

## Support

For issues or questions:
1. Check the Troubleshooting section above
2. Review FluxCD logs: `flux logs --level=error`
3. Run verification script: `./verify-deployment.sh`
4. Check component documentation

## License

This setup is provided as-is for demonstration and educational purposes.
