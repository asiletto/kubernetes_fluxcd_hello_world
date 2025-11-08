# FluxCD GitOps Deployment per K3s

Questo repository contiene una configurazione GitOps pronta per la produzione utilizzando FluxCD per il deployment di applicazioni su K3s, con una chiara separazione tra componenti infrastrutturali e applicativi.

## Panoramica dell'Architettura

### Struttura del Repository

```
.
├── clusters/
│   └── k3s-local/                      # Configurazione specifica del cluster
│       ├── flux-system/                # Bootstrap FluxCD (auto-generato)
│       ├── infrastructure.yaml         # Kustomization Infrastruttura
│       ├── infrastructure-config.yaml  # Kustomization Configurazione Infrastruttura
│       └── applications.yaml           # Kustomization Applicazioni (dipende da infra)
│
├── infrastructure/                     # Componenti infrastrutturali
│   ├── sources/
│   │   ├── helm-repos.yaml            # Sorgenti repository Helm
│   │   └── kustomization.yaml
│   ├── namespaces/
│   │   ├── namespaces.yaml            # Tutti i namespace
│   │   └── kustomization.yaml
│   ├── nginx-ingress/
│   │   ├── release.yaml               # HelmRelease NGINX Ingress
│   │   └── kustomization.yaml
│   ├── cert-manager/
│   │   ├── release.yaml               # HelmRelease cert-manager
│   │   └── kustomization.yaml
│   ├── cert-manager-config/
│   │   ├── issuers.yaml               # ClusterIssuer Let's Encrypt
│   │   └── kustomization.yaml
│   └── kustomization.yaml             # Kustomization principale infrastruttura
│
├── apps/                              # Componenti applicativi
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
├── reset-k3s.sh                       # Pulizia e reinstallazione k3s
├── bootstrap-flux.sh                  # Bootstrap FluxCD
├── create-secrets.sh                  # Creazione secret richiesti
├── verify-deployment.sh               # Verifica stato deployment
└── README.md                          # Questo file
```

### Separazione dei Componenti

#### Componenti Infrastrutturali
- **NGINX Ingress Controller**: Gestisce il routing del traffico HTTP/HTTPS
- **cert-manager**: Automatizza il provisioning di certificati TLS via Let's Encrypt
- **ClusterIssuer**: Issuer Let's Encrypt staging e production
- Deployati in namespace dedicati: `ingress-nginx`, `cert-manager`

#### Componenti Applicativi
- **nginx-red**: Applicazione demo con sfondo rosso
- **nginx-blue**: Applicazione demo con sfondo blu
- Ogni applicazione deployata nel proprio namespace
- Ogni applicazione ha la propria risorsa Ingress con TLS

## Prerequisiti

### Strumenti Richiesti
- **k3s**: Kubernetes leggero (o installazione pulita via `reset-k3s.sh`)
- **flux CLI**: Tool command-line FluxCD
  ```bash
  curl -s https://fluxcd.io/install.sh | sudo bash
  ```
- **kubectl**: Kubernetes CLI (incluso con k3s)
- **git**: Controllo versione

### Account e Token Richiesti
1. **Account GitHub**: Per hosting del repository
2. **GitHub Personal Access Token**:
   - Crea su: https://github.com/settings/tokens/new
   - Permessi richiesti: `repo` (accesso completo)
3. **Account Cloudflare**: Per gestione DNS
4. **Cloudflare API Token**:
   - Crea su: https://dash.cloudflare.com/profile/api-tokens
   - Template: "Edit zone DNS"
   - Permessi:
     - Zone / DNS / Edit
     - Zone / Zone / Read
   - Zone: `300510300.xyz`

### Configurazione DNS
Assicurati che i seguenti record DNS siano configurati in Cloudflare:

```
test-nginx.300510300.xyz         A    192.168.1.100
test-nginx-another.300510300.xyz A    192.168.1.100
```

## Guida Rapida

### Step 1: Reset K3s (Opzionale)

Se vuoi iniziare con un cluster pulito:

```bash
./reset-k3s.sh
```

Questo:
- Disinstalla k3s esistente
- Pulisce tutti i file residui
- Reinstalla k3s con la configurazione corretta
- Verifica che il cluster sia pronto

### Step 2: Bootstrap FluxCD

```bash
export GITHUB_USER="tuo-username-github"
export GITHUB_REPO="02_flux_github"
export GITHUB_TOKEN="ghp_xxxxxxxxxxxxx"

./bootstrap-flux.sh
```

Questo:
- Verifica i prerequisiti
- Esegue controlli pre-flight FluxCD
- Bootstrap di FluxCD nel cluster
- Configura la sorgente GitRepository
- Deploy delle Kustomization iniziali

### Step 3: Creazione Secret

```bash
export CLOUDFLARE_API_TOKEN="tuo-cloudflare-api-token"

./create-secrets.sh
```

Questo crea:
- Secret `cloudflare-api-token` nel namespace `cert-manager`

**Importante**: I secret NON sono memorizzati in Git e devono essere ricreati dopo i reset del cluster.

### Step 4: Commit e Push

```bash
git add .
git commit -m "Setup iniziale FluxCD"
git push origin main
```

FluxCD automaticamente:
1. Rileva il push
2. Riconcilia i componenti infrastrutturali
3. Attende che l'infrastruttura sia healthy
4. Deploya i componenti applicativi
5. Richiede certificati TLS da Let's Encrypt

### Step 5: Verifica Deployment

```bash
./verify-deployment.sh
```

O monitora in tempo reale:

```bash
flux get kustomizations --watch
```

## Flusso di Deployment

### Come Funziona GitOps

```
Developer                  GitHub                    FluxCD                   Cluster K8s
    |                         |                         |                          |
    |-- git push ------------>|                         |                          |
    |                         |                         |                          |
    |                         |<-- poll (ogni 1m) -----|                          |
    |                         |                         |                          |
    |                         |--- modifiche rilevate ->|                          |
    |                         |                         |                          |
    |                         |                         |-- riconciliazione ------>|
    |                         |                         |                          |
    |                         |                         |<-- stato ---------------|
    |                         |                         |                          |
    |                         |<-- stato commit --------|                          |
```

### Catena di Dipendenze

```
Infrastructure Kustomization
  ├── Namespace (creati per primi)
  ├── Repository Helm
  ├── NGINX Ingress Controller (HelmRelease)
  │   └── Attesa deployment pronto
  └── cert-manager (HelmRelease)
      └── Attesa deployment pronto

Infrastructure-Config Kustomization (dipende da Infrastructure)
  └── ClusterIssuer (creati dopo che cert-manager è pronto)

Applications Kustomization (dipende da Infrastructure-Config)
  ├── nginx-red
  │   ├── ConfigMap
  │   ├── Deployment
  │   ├── Service
  │   └── Ingress (innesca richiesta certificato)
  └── nginx-blue
      ├── ConfigMap
      ├── Deployment
      ├── Service
      └── Ingress (innesca richiesta certificato)
```

## Dettagli Configurazione

### Configurazione Infrastruttura

#### NGINX Ingress Controller
- **Versione**: 4.11.x (app version 1.11.1)
- **Tipo Service**: LoadBalancer (k3s ServiceLB)
- **IP Esterno**: 192.168.1.100
- **Porte**: 80 (HTTP), 443 (HTTPS)
- **Sicurezza**: Annotazioni snippet disabilitate, non-root, filesystem root read-only

#### cert-manager
- **Versione**: 1.13.x
- **CRD**: Installate e gestite da Helm
- **Tipo Challenge**: DNS-01 (via Cloudflare)
- **Issuer**:
  - `letsencrypt-staging`: Per test (certificati non fidati)
  - `letsencrypt-prod`: Per produzione (certificati fidati)

### Configurazione Applicazioni

#### nginx-red
- **Namespace**: `nginx-red`
- **Repliche**: 2
- **Immagine**: `nginx:1.27-alpine`
- **Hostname**: `test-nginx.300510300.xyz`
- **Sfondo**: Rosso (#dc2626)

#### nginx-blue
- **Namespace**: `nginx-blue`
- **Repliche**: 2
- **Immagine**: `nginx:1.27-alpine`
- **Hostname**: `test-nginx-another.300510300.xyz`
- **Sfondo**: Blu (#2563eb)

## Gestione del Deployment

### Operazioni Comuni

#### Forzare Riconciliazione

```bash
# Riconcilia tutto
flux reconcile kustomization flux-system --with-source

# Riconcilia solo infrastruttura
flux reconcile kustomization infrastructure --with-source

# Riconcilia solo configurazione infrastruttura
flux reconcile kustomization infrastructure-config --with-source

# Riconcilia solo applicazioni
flux reconcile kustomization applications --with-source
```

#### Visualizzare Log

```bash
# Tutti i log FluxCD
flux logs --all-namespaces --follow

# Componente specifico
kubectl logs -n flux-system deployment/source-controller -f
```

#### Controllare Stato Risorse

```bash
# Risorse FluxCD
flux get all

# Release Helm
kubectl get helmreleases -A

# Certificati
kubectl get certificates -A
kubectl describe certificate -n nginx-red nginx-red-tls-cert
```

#### Sospendere/Riprendere Riconciliazione

```bash
# Sospendi (ferma aggiornamenti automatici)
flux suspend kustomization applications

# Riprendi
flux resume kustomization applications
```

### Apportare Modifiche

1. **Modifica manifest** nel repository locale
2. **Commit modifiche**: `git commit -am "Descrizione modifiche"`
3. **Push su GitHub**: `git push origin main`
4. **Attendi riconciliazione** (automatica, ogni 1m) o forza:
   ```bash
   flux reconcile kustomization applications --with-source
   ```

### Rollback Modifiche

```bash
# Revert commit git
git revert HEAD
git push origin main

# Oppure forza riconciliazione a un commit specifico
flux reconcile kustomization applications --with-source
```

## Troubleshooting

### Problemi FluxCD

```bash
# Controlla salute FluxCD
flux check

# Visualizza stato riconciliazione
flux get kustomizations

# Visualizza stato sorgenti
flux get sources git

# Controlla errori
flux logs --level=error
```

### Problemi Infrastruttura

```bash
# Controlla release Helm
flux get helmreleases -A

# Visualizza dettagli HelmRelease
kubectl describe helmrelease ingress-nginx -n ingress-nginx

# Controlla stato pod
kubectl get pods -n ingress-nginx
kubectl get pods -n cert-manager
```

### Problemi Certificati

```bash
# Controlla stato certificati
kubectl get certificates -A
kubectl describe certificate nginx-red-tls-cert -n nginx-red

# Controlla richieste certificati
kubectl get certificaterequests -A

# Controlla log cert-manager
kubectl logs -n cert-manager deployment/cert-manager -f

# Verifica secret Cloudflare
kubectl get secret cloudflare-api-token -n cert-manager
kubectl describe secret cloudflare-api-token -n cert-manager
```

### Problemi Applicazioni

```bash
# Controlla log pod
kubectl logs -n nginx-red deployment/nginx-red
kubectl logs -n nginx-blue deployment/nginx-blue

# Controlla stato ingress
kubectl get ingress -A
kubectl describe ingress nginx-red-ingress -n nginx-red

# Test connettività
curl -k -H 'Host: test-nginx.300510300.xyz' https://192.168.1.100
```

### Problemi Comuni

#### Certificati Non Pronti
- **Sintomo**: Stato certificato mostra "False"
- **Causa**: Challenge DNS-01 fallita
- **Soluzioni**:
  1. Verifica che il token API Cloudflare sia corretto
  2. Controlla che i record DNS siano configurati
  3. Visualizza dettagli challenge: `kubectl describe challenge -A`
  4. Controlla log cert-manager

#### HelmRelease Fallita
- **Sintomo**: `flux get helmreleases` mostra "False"
- **Causa**: Installazione/aggiornamento chart Helm fallito
- **Soluzioni**:
  1. Controlla eventi HelmRelease: `kubectl describe helmrelease <nome> -n <namespace>`
  2. Verifica che il repository Helm sia accessibile: `flux get sources helm`
  3. Controlla log pod del componente fallito

#### Kustomization Non Riconcilia
- **Sintomo**: Modifiche non applicate
- **Causa**: Problemi sorgente o dipendenze
- **Soluzioni**:
  1. Controlla sorgente GitRepository: `flux get sources git`
  2. Verifica che le dipendenze siano healthy: `flux get kustomizations`
  3. Forza riconciliazione: `flux reconcile kustomization <nome> --with-source`

## Test

### Test Redirect HTTP → HTTPS

```bash
curl -I -H 'Host: test-nginx.300510300.xyz' http://192.168.1.100
# Dovrebbe ritornare 308 Permanent Redirect a https://
```

### Test Endpoint HTTPS

```bash
# Via IP LoadBalancer
curl -H 'Host: test-nginx.300510300.xyz' https://192.168.1.100
curl -H 'Host: test-nginx-another.300510300.xyz' https://192.168.1.100

# Via DNS (se configurato)
curl https://test-nginx.300510300.xyz
curl https://test-nginx-another.300510300.xyz
```

### Verifica Certificato

```bash
echo | openssl s_client -servername test-nginx.300510300.xyz -connect 192.168.1.100:443 2>/dev/null | openssl x509 -noout -text
```

## Pulizia

### Rimuovi Solo Applicazioni

```bash
flux delete kustomization applications --silent
kubectl delete namespace nginx-red nginx-blue
```

### Rimuovi Infrastruttura

```bash
flux delete kustomization infrastructure-config --silent
flux delete kustomization infrastructure --silent
kubectl delete namespace ingress-nginx cert-manager
```

### Pulizia Completa (incluso FluxCD)

```bash
flux uninstall --silent
```

### Reset Completo Cluster

```bash
./reset-k3s.sh
```

## Considerazioni sulla Sicurezza

### Gestione Secret

Il setup attuale usa **secret manuali** (non memorizzati in Git). Per la produzione, considera:

- **Sealed Secrets**: Cripta secret in Git
- **SOPS**: Cripta file YAML con age/GPG
- **External Secrets Operator**: Sincronizza da archivi secret esterni (Vault, AWS Secrets Manager)

### Network Policy

Considera l'aggiunta di NetworkPolicy per restringere il traffico tra namespace:

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

### Sicurezza Immagini

Considera l'aggiunta di:
- **Scansione immagini**: Scansiona immagini per vulnerabilità
- **Firma immagini**: Verifica firme immagini
- **Policy immagini**: Limita quali immagini possono essere deployate

## Miglioramenti Futuri

### Monitoring & Observability

Aggiungi Prometheus e Grafana per monitoring:

```
infrastructure/
└── monitoring/
    ├── prometheus/
    ├── grafana/
    └── kustomization.yaml
```

### Multi-Ambiente

Estendi a più ambienti:

```
clusters/
├── k3s-dev/
├── k3s-staging/
└── k3s-prod/
```

### Aggiornamenti Immagini Automatici

Abilita ImageRepository e ImagePolicy di Flux per aggiornamenti automatici:

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

## Riferimenti

- [Documentazione FluxCD](https://fluxcd.io/docs/)
- [Documentazione K3s](https://docs.k3s.io/)
- [Documentazione cert-manager](https://cert-manager.io/docs/)
- [Documentazione NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [Documentazione Kustomize](https://kustomize.io/)

