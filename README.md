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

## Repository Proxy Locale (Opzionale)

Questo setup supporta l'utilizzo di repository proxy locali per ridurre l'utilizzo di banda esterna e migliorare le performance. I proxy sono gestiti tramite container Docker esterni al cluster K3s.

### Panoramica

Il sistema utilizza due servizi proxy:

1. **Docker Registry** (porta 5000): Pull-through cache per immagini container
   - Caches automaticamente immagini da Docker Hub, GHCR, registry.k8s.io, Quay.io
   - Trasparente per le applicazioni (via K3s registry mirrors)
   - Persistente su volume Docker

2. **ChartMuseum** (porta 8080): Repository per Helm charts
   - Richiede caricamento manuale dei charts
   - FluxCD configurato per utilizzarlo al posto dei repository upstream
   - API REST per gestione charts

### Setup Rapido

```bash
# 1. Avvia i servizi proxy
cd proxy-setup/
docker compose up -d

# 2. Verifica che i servizi siano attivi
docker compose ps
curl http://localhost:5000/v2/_catalog  # Docker Registry
curl http://localhost:8080/health        # ChartMuseum

# 3. Popola ChartMuseum con i charts necessari
cd ..
./proxy-setup/populate-chartmuseum.sh

# 4. Configura K3s per usare il registry proxy
# IMPORTANTE: Usa l'IP della tua macchina, non localhost!
# Esempio: sudo REGISTRY_HOST=192.168.1.50 ./setup-registry-mirrors.sh
sudo REGISTRY_HOST=<tuo-ip> ./setup-registry-mirrors.sh

# 5. Aggiorna la configurazione FluxCD
sed -i 's/CHARTMUSEUM_HOST/<tuo-ip>/g' infrastructure/sources/helm-repos.yaml

# 6. Commit e push
git add infrastructure/sources/helm-repos.yaml
git commit -m "Configura repository proxy locale"
git push origin main

# 7. Verifica il setup
REGISTRY_HOST=<tuo-ip> CHARTMUSEUM_HOST=<tuo-ip> ./verify-proxies.sh
```

### Struttura File Proxy

```
proxy-setup/
├── docker-compose.yml           # Definizione servizi Docker Registry e ChartMuseum
├── populate-chartmuseum.sh      # Script per caricare charts in ChartMuseum
└── README (vedi CLAUDE.md)

setup-registry-mirrors.sh        # Configura K3s per usare il registry proxy
registries.yaml.template         # Template configurazione registry mirrors
verify-proxies.sh                # Verifica che i proxy funzionino correttamente
```

### Configurazione K3s Registry Mirrors

Il file `/etc/rancher/k3s/registries.yaml` configura K3s per usare il proxy:

```yaml
mirrors:
  docker.io:
    endpoint:
      - "http://192.168.1.50:5000"
  ghcr.io:
    endpoint:
      - "http://192.168.1.50:5000"
  registry.k8s.io:
    endpoint:
      - "http://192.168.1.50:5000"
  quay.io:
    endpoint:
      - "http://192.168.1.50:5000"
```

**Nota**: Sostituisci `192.168.1.50` con l'IP della tua macchina host.

### Gestione ChartMuseum

#### Aggiungere Nuove Versioni di Chart

Quando aggiorni le versioni nei HelmRelease:

```bash
# Scarica il nuovo chart
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm pull ingress-nginx/ingress-nginx --version 4.12.0

# Carica su ChartMuseum
curl --data-binary "@ingress-nginx-4.12.0.tgz" http://localhost:8080/api/charts

# Verifica caricamento
curl http://localhost:8080/api/charts/ingress-nginx
```

#### Visualizzare Charts Disponibili

```bash
# Lista tutti i charts
curl http://localhost:8080/api/charts | jq

# Dettagli specifico chart
curl http://localhost:8080/api/charts/ingress-nginx
```

### Verifica Funzionamento

```bash
# Controlla stato container
docker compose ps

# Testa pull attraverso il registry proxy
sudo k3s crictl pull nginx:1.27-alpine
docker logs docker-registry  # Verifica cache hit

# Verifica FluxCD HelmRepository
flux get sources helm -A

# Test completo
./verify-proxies.sh
```

### Manutenzione

#### Svuotare Cache Registry

```bash
cd proxy-setup/
docker compose down
docker volume rm proxy-setup_registry-data
docker compose up -d
```

#### Backup Charts ChartMuseum

```bash
# I charts sono nel volume Docker
docker run --rm -v proxy-setup_chartmuseum-data:/data -v $(pwd):/backup alpine tar czf /backup/chartmuseum-backup.tar.gz /data
```

### Ripristino Repository Upstream

Per tornare a utilizzare i repository upstream:

1. **Helm Charts**: Decommenta gli URL originali in `infrastructure/sources/helm-repos.yaml`
2. **Container Images**: Rimuovi `/etc/rancher/k3s/registries.yaml` e riavvia K3s
3. Commit e push

### Troubleshooting Proxy

#### ChartMuseum non raggiungibile da FluxCD

```bash
# Verifica HelmRepository status
flux get sources helm -A
kubectl describe helmrepository ingress-nginx -n flux-system

# Verifica che ChartMuseum sia accessibile dal cluster
kubectl run test-curl --rm -it --image=curlimages/curl -- curl http://<chartmuseum-ip>:8080/health
```

#### Immagini non usano il proxy

```bash
# Verifica configurazione K3s
sudo cat /etc/rancher/k3s/registries.yaml

# Controlla logs K3s
sudo journalctl -u k3s -f | grep registry

# Testa connettività dal nodo
curl http://<registry-ip>:5000/v2/_catalog
```

Per troubleshooting dettagliato e configurazione avanzata, consulta `CLAUDE.md` sezione "Local Repository Proxies".

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

