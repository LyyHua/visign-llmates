# DevOps Project: Deploy Visign (Next.js + FastAPI AI) on Azure AKS

> Complete step-by-step guide: Docker → Bicep IaC → K8s Manifests → GitHub Actions CI/CD → Prometheus+Grafana Monitoring

---

## TABLE OF CONTENTS

**Stage 0:** Prerequisites & Repository Setup  
**Stage 1:** Docker Images (visign-web, visign-ai)  
**Stage 2:** Bicep IaC — Provision Azure Infrastructure (AKS, ACR, Key Vault)  
**Stage 3:** Kubernetes Manifests (Deployment/Service/Ingress + 2 Replicas across 2 AZs)  
**Stage 4:** Key Vault Runtime Secrets  
**Stage 5:** CI with GitHub Actions  
**Stage 6:** Pull-based CD with ArgoCD  
**Stage 7:** Prometheus + Grafana Monitoring  

---

## Architecture Overview

```
┌─────────────┐    push    ┌──────┐    pull     ┌───────────────────────┐
│ GitHub Repo │───────────►│  ACR │◄────────────│       AKS Cluster     │
│ (source)    │            └──────┘             │  ┌─────────────────┐  │
└──────┬──────┘                                 │  │  visign-web (x2)│  │
       │  trigger                               │  │  (Next.js)      │  │
       ▼                                        │  ├─────────────────┤  │
┌──────────────┐                                │  │  visign-ai (x2) │  │
│GitHub Actions│ ──update manifests in Git─────►│  │  (FastAPI)      │  │
│      CI      │                                │  ├─────────────────┤  │
└──────────────┘                                │  │  Prometheus     │  │
                                                │  │  Grafana        │  │
       ┌────────────┐                           │  ├─────────────────┤  │
       │ Key Vault  │◄─────secrets──────────────│  │  Ingress (nginx)│  │
       └────────────┘                           │  └─────────────────┘  │
                                                │   Zone A  │  Zone B   │
                                                └───────────────────────┘
```

### Optional Requirement Snapshot

_Quick reference only (non-blocking)._

1. Chủ đề: Triển khai ứng dụng Visign (Next.js + FastAPI AI) theo hướng DevOps trên Azure AKS với CI/CD GitHub Actions, ACR, Key Vault và giám sát Prometheus-Grafana.
2. Nội dung:
- Đóng gói 2 service (visign-web, visign-ai) thành Docker images và lưu trữ trên Azure Container Registry (ACR).
- Dùng Bicep (IaC) triển khai hạ tầng Azure: AKS (2 Availability Zones), ACR, Key Vault và cấu hình networking tối thiểu.
- Triển khai ứng dụng lên AKS bằng Kubernetes manifests (Deployment/Service/Ingress), cấu hình 2 replicas phân bố 2 AZ, inject secrets qua Key Vault.
- Xây dựng CI/CD bằng GitHub Actions (GitOps): build -> push ACR -> deploy AKS theo nhánh/tag.
- Thiết lập monitoring Prometheus + Grafana cho hệ thống (dashboard và cảnh báo cơ bản).
3. Kết quả:
- Visign chạy ổn định trên AKS với High Availability cơ bản nhờ 2 replicas phân bố 2 AZ.
- CI/CD tự động hoá: build/push/deploy nhanh, giảm thao tác thủ công.
- Hạ tầng được quản lý bằng Bicep, dễ tái tạo và mở rộng.
- Có giám sát bằng Prometheus-Grafana và quản lý secrets tập trung bằng Key Vault.

---

## Stage 0: Prerequisites & Repository Setup

### What You Need Installed

```bash
# 1. Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
# OR on Windows: winget install -e --id Microsoft.AzureCLI

# 2. kubectl
az aks install-cli

# 3. Docker Engine (for local testing)
# Linux (Fedora): sudo dnf install -y docker docker-buildx docker-compose-plugin
# Linux (Debian/Ubuntu): follow https://docs.docker.com/engine/install/
# Start/enable daemon: sudo systemctl enable --now docker

# 4. Bicep CLI (comes with Azure CLI 2.20+, verify:)
az bicep version
# If not installed:
az bicep install

# 5. Helm (for Prometheus/Grafana)
# Windows: winget install Helm.Helm
# Linux:
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Login to Azure

```bash
az login
# Set your subscription
az account set --subscription "<YOUR_SUBSCRIPTION_ID>"
```

### Repository Structure

We'll work from the `visign-llmates` repo (the combined repo). Your final repo structure should look like:

```
visign-llmates/
├── ai-model/                    # FastAPI AI service
│   ├── Dockerfile               # ✅ Already exists (needs improvement)
│   ├── app.py
│   ├── requirements.txt
│   └── ...
├── visign/                      # Next.js web service
│   ├── Dockerfile               # ✅ Already exists (needs major improvement)
│   ├── package.json
│   └── ...
├── nginx/                       # Nginx config (for K8s Ingress, not needed as container)
│   └── default.conf
├── k8s-specifications/                         # 🆕 Kubernetes manifests
│   ├── namespace.yaml
│   ├── visign-web-deployment.yaml
│   ├── visign-web-service.yaml
│   ├── visign-ai-deployment.yaml
│   ├── visign-ai-service.yaml
│   ├── ingress.yaml
│   └── secrets-provider.yaml
├── infra/                       # 🆕 Bicep IaC files
│   ├── main.bicep
│   ├── modules/
│   │   ├── aks.bicep
│   │   ├── acr.bicep
│   │   └── keyvault.bicep
│   └── parameters.json
├── monitoring/                  # 🆕 Prometheus + Grafana
│   ├── prometheus-values.yaml
│   └── grafana-dashboard.json
├── .github/                     # 🆕 GitHub Actions CI/CD
│   └── workflows/
│       ├── ci-cd-web.yml
│       └── ci-cd-ai.yml
└── docker-compose.yml           # ✅ Already exists (for local dev)
```

---

## Stage 1: Docker Images

### 1A. Fix the AI Model Dockerfile (`ai-model/Dockerfile`)

Your current Dockerfile is mostly fine but needs a production-ready upgrade:

```dockerfile
# ai-model/Dockerfile
FROM python:3.11-slim

WORKDIR /app

ARG TORCH_COMPUTE

RUN test -n "$TORCH_COMPUTE" || (echo "ERROR: Missing required build arg TORCH_COMPUTE (cpu|gpu)" >&2; exit 1)
RUN case "$TORCH_COMPUTE" in cpu|gpu) ;; *) echo "ERROR: TORCH_COMPUTE must be cpu or gpu" >&2; exit 1 ;; esac

# Install system dependencies for OpenCV and MediaPipe
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Install torch by target compute
# cpu: smaller image and faster deploy on CPU node pools
# gpu: CUDA wheel for GPU node pools
RUN pip install --no-cache-dir --upgrade pip && \
  if [ "$TORCH_COMPUTE" = "gpu" ]; then \
    pip install --no-cache-dir --default-timeout=300 --index-url https://download.pytorch.org/whl/cu121 torch; \
  else \
    pip install --no-cache-dir --default-timeout=300 --index-url https://download.pytorch.org/whl/cpu torch; \
  fi

# Runtime dependencies only (smaller image and faster build)
COPY requirements.runtime.txt .
RUN pip install --no-cache-dir --default-timeout=120 -r requirements.runtime.txt

# Copy application code
COPY . .

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/docs')" || exit 1

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]
```

> **⚠️ IMPORTANT:** Your AI model file (`lstm_150.pt`) needs to be included in the Docker image. Make sure it's in the `ai-model/artifacts/` directory and NOT in `.gitignore`. If the model file is too large for Git, you'll need to use Git LFS or download it at container startup.

### 1B. Rewrite the Next.js Dockerfile (`visign/Dockerfile`)

Your current Dockerfile is barebones (`COPY . .` + `npm start`). It doesn't even build the app! Here's a proper multi-stage production Dockerfile:

```dockerfile
# visign/Dockerfile
# Stage 1: Install dependencies
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --include=dev

# Stage 2: Build the application
FROM node:20-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY package.json package-lock.json ./
COPY . .

# Required build-time args (no defaults, fail fast if missing)
ARG DATABASE_URL
ARG OPENAI_API_KEY
ARG NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY

RUN test -n "$DATABASE_URL" || (echo "ERROR: Missing required build arg DATABASE_URL" >&2; exit 1)
RUN test -n "$OPENAI_API_KEY" || (echo "ERROR: Missing required build arg OPENAI_API_KEY" >&2; exit 1)
RUN test -n "$NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY" || (echo "ERROR: Missing required build arg NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY" >&2; exit 1)

ENV DATABASE_URL=$DATABASE_URL
ENV OPENAI_API_KEY=$OPENAI_API_KEY
ENV NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=$NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY
ENV NEXT_TELEMETRY_DISABLED=1

RUN npm run build

# Stage 3: Production image
FROM node:20-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV HOSTNAME=0.0.0.0

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# Copy built assets
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static

USER nextjs

EXPOSE 3000
ENV PORT=3000

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:3000/ || exit 1

CMD ["node", "server.js"]
```

> **⚠️ CRITICAL:** For the standalone output to work, you MUST add `output: 'standalone'` to your `next.config.mjs`:

```javascript
// visign/next.config.mjs
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'standalone',  // ← ADD THIS LINE
  eslint: {
    ignoreDuringBuilds: true,
  },
  // ... rest of your existing config
};
export default nextConfig;
```

### 1C. Test Docker Images Locally

```bash
cd visign-llmates

# Copy sample env to local env file.
cp .env.example .env
# Then edit .env with your real credentials/values:
# TORCH_COMPUTE, DATABASE_URL, OPENAI_API_KEY, NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY

docker compose build

# Test locally
docker compose up -d
docker compose ps
```

---

## Stage 2: Bicep IaC — Provision Azure Infrastructure

### 2A. Project Parameters File (`infra/parameters.json`)

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "projectName": { "value": "visign" },
    "location": { "value": "southeastasia" },
    "aksNodeCount": { "value": 2 },
    "aksNodeVMSize": { "value": "Standard_B2s" }
  }
}
```

### 2B. ACR Module (`infra/modules/acr.bicep`)

```bicep
@description('Name of the container registry')
param acrName string

@description('Location for the registry')
param location string

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
  }
}

output acrId string = acr.id
output acrLoginServer string = acr.properties.loginServer
output acrName string = acr.name
```

### 2C. Key Vault Module (`infra/modules/keyvault.bicep`)

```bicep
@description('Name of the Key Vault')
param keyVaultName string

@description('Location')
param location string

@description('AKS Kubelet Identity Object ID for Key Vault access')
param aksKubeletIdentityObjectId string

@description('Tenant ID')
param tenantId string = subscription().tenantId

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
  }
}

// Grant AKS identity access to Key Vault secrets
resource kvSecretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, aksKubeletIdentityObjectId, 'Key Vault Secrets User')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: aksKubeletIdentityObjectId
    principalType: 'ServicePrincipal'
  }
}

output keyVaultId string = keyVault.id
output keyVaultUri string = keyVault.properties.vaultUri
output keyVaultName string = keyVault.name
```

### 2D. AKS Module (`infra/modules/aks.bicep`)

```bicep
@description('Name of the AKS cluster')
param aksName string

@description('Location')
param location string

@description('Node count')
param nodeCount int = 2

@description('VM size')
param nodeVMSize string = 'Standard_B2s'

@description('Availability zones for AKS system node pool')
param nodeAvailabilityZones array

@description('ACR ID to attach')
param acrId string

resource aks 'Microsoft.ContainerService/managedClusters@2024-01-01' = {
  name: aksName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: aksName
    agentPoolProfiles: [
      {
        name: 'agentpool'
        count: nodeCount
        vmSize: nodeVMSize
        osType: 'Linux'
        mode: 'System'
        availabilityZones: nodeAvailabilityZones
        enableAutoScaling: true
        minCount: 2
        maxCount: 4
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      loadBalancerSku: 'standard'
    }
    addonProfiles: {
      azureKeyvaultSecretsProvider: {
        enabled: true
        config: {
          enableSecretRotation: 'true'
          rotationPollInterval: '2m'
        }
      }
    }
  }
}

// Attach ACR to AKS (AcrPull role)
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aks.id, acrId, 'AcrPull')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: aks.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
  }
}

output aksName string = aks.name
output aksId string = aks.id
output kubeletIdentityObjectId string = aks.properties.identityProfile.kubeletidentity.objectId
```

### 2E. Main Bicep File (`infra/main.bicep`)

```bicep
@description('Project name used as prefix')
param projectName string

@description('Azure region')
param location string = resourceGroup().location

@description('AKS node count')
param aksNodeCount int = 2

@description('AKS node VM size')
param aksNodeVMSize string = 'Standard_B2s'

@description('AKS availability zones for the system node pool')
param aksAvailabilityZones array

// Variables
var acrName = '${projectName}acr${uniqueString(resourceGroup().id)}'
var aksName = '${projectName}-aks'
var kvName = '${projectName}-kv-${uniqueString(resourceGroup().id)}'

// Deploy ACR
module acr 'modules/acr.bicep' = {
  name: 'deploy-acr'
  params: {
    acrName: acrName
    location: location
  }
}

// Deploy AKS
module aks 'modules/aks.bicep' = {
  name: 'deploy-aks'
  params: {
    aksName: aksName
    location: location
    nodeCount: aksNodeCount
    nodeVMSize: aksNodeVMSize
    nodeAvailabilityZones: aksAvailabilityZones
    acrId: acr.outputs.acrId
  }
}

// Deploy Key Vault
module keyVault 'modules/keyvault.bicep' = {
  name: 'deploy-keyvault'
  params: {
    keyVaultName: kvName
    location: location
    aksKubeletIdentityObjectId: aks.outputs.kubeletIdentityObjectId
  }
}

// Outputs
output acrLoginServer string = acr.outputs.acrLoginServer
output aksName string = aks.outputs.aksName
output keyVaultName string = keyVault.outputs.keyVaultName
output keyVaultUri string = keyVault.outputs.keyVaultUri
```

### 2F. Subscription Bootstrap Bicep (`infra/main.subscription.bicep`)

Use this file to keep resource group creation in IaC as well (no manual `az group create`).

```bicep
targetScope = 'subscription'

@description('Resource group name for all Visign infrastructure')
param resourceGroupName string = 'visign-rg'

@description('Project name used as prefix')
param projectName string = 'visign'

@description('Azure region')
param location string = 'southeastasia'

@description('AKS node count')
param aksNodeCount int = 2

@description('AKS node VM size')
param aksNodeVMSize string = 'Standard_B2s'

@description('AKS availability zones for the system node pool')
param aksAvailabilityZones array = [
  '2'
  '3'
]

resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: resourceGroupName
  location: location
}

module platform './main.bicep' = {
  name: 'deploy-visign-platform'
  scope: rg
  params: {
    projectName: projectName
    location: location
    aksNodeCount: aksNodeCount
    aksNodeVMSize: aksNodeVMSize
    aksAvailabilityZones: aksAvailabilityZones
  }
}
```

### 2G. Deploy Infrastructure

```bash
# 1. Deploy subscription-scope bootstrap (creates RG + deploys platform module)
# Uses defaults from infra/main.subscription.bicepparam
az deployment sub create \
  --location southeastasia \
  --template-file infra/main.subscription.bicep \
  --parameters infra/main.subscription.bicepparam

# 2. Get outputs
az deployment group show \
  --resource-group visign-rg \
  --name deploy-visign-platform \
  --query properties.outputs

# 3. Connect to AKS
az aks get-credentials --resource-group visign-rg --name visign-aks --overwrite-existing

# 4. Verify
kubectl get nodes
# You should see 2 nodes across 2 availability zones
```
> **💡 TIP:** Run `kubectl describe nodes | grep -e "Name:" -e "topology.kubernetes.io/zone"` to verify nodes are in different AZs.

### 2G.1 Hard check for 2-AZ requirement (Pass/Fail)

Use this check before marking the requirement complete.

```bash
# Shows each node and its zone label
kubectl get nodes -L topology.kubernetes.io/zone

# Count unique zones represented by Ready nodes (Linux/macOS)
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}{end}' \
  | sort -u | wc -l
```

Pass criteria:

- At least 2 unique zone values are present.
- Each workload has `replicas: 2` and `topologySpreadConstraints` using `topology.kubernetes.io/zone`.

If only 1 zone appears, do not claim 2-AZ compliance yet. Check cluster creation inputs in `infra/main.subscription.bicepparam` and node pool distribution.

---

## Stage 3: Kubernetes Manifests

### 3A. Namespace (`k8s-specifications/namespace.yaml`)

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: visign
  labels:
    app.kubernetes.io/part-of: visign
```

### 3B. AI Service Deployment (`k8s-specifications/visign-ai-deployment.yaml`)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: visign-ai
  namespace: visign
  labels:
    app: visign-ai
spec:
  replicas: 2
  selector:
    matchLabels:
      app: visign-ai
  template:
    metadata:
      labels:
        app: visign-ai
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8000"
        prometheus.io/path: "/metrics"
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app: visign-ai
      containers:
        - name: visign-ai
          image: __ACR_LOGIN_SERVER__/visign-ai:latest   # replaced by CI/CD
          ports:
            - containerPort: 8000
          resources:
            requests:
              cpu: "250m"
              memory: "512Mi"
            limits:
              cpu: "1000m"
              memory: "2Gi"
          readinessProbe:
            httpGet:
              path: /docs
              port: 8000
            initialDelaySeconds: 30
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /docs
              port: 8000
            initialDelaySeconds: 60
            periodSeconds: 30
```

### 3C. AI Service (`k8s-specifications/visign-ai-service.yaml`)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: visign-ai
  namespace: visign
  labels:
    app: visign-ai
spec:
  selector:
    app: visign-ai
  ports:
    - port: 8000
      targetPort: 8000
      protocol: TCP
  type: ClusterIP
```

### 3D. Web Deployment (`k8s-specifications/visign-web-deployment.yaml`)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: visign-web
  namespace: visign
  labels:
    app: visign-web
spec:
  replicas: 2
  selector:
    matchLabels:
      app: visign-web
  template:
    metadata:
      labels:
        app: visign-web
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app: visign-web
      containers:
        - name: visign-web
          image: __ACR_LOGIN_SERVER__/visign-web:latest   # replaced by CI/CD
          ports:
            - containerPort: 3000
          volumeMounts:
            - name: secrets-store
              mountPath: "/mnt/secrets-store"
              readOnly: true
          env:
            - name: NODE_ENV
              value: "production"
            - name: NEXT_PUBLIC_API_URL
              value: "http://visign-ai:8000"
            - name: MODEL_SERVER_URL
              value: "http://visign-ai:8000"
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: visign-secrets
                  key: DATABASE_URL
            - name: NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY
              valueFrom:
                secretKeyRef:
                  name: visign-secrets
                  key: NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY
            - name: CLERK_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: visign-secrets
                  key: CLERK_SECRET_KEY
          resources:
            requests:
              cpu: "200m"
              memory: "256Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
          readinessProbe:
            httpGet:
              path: /
              port: 3000
            initialDelaySeconds: 15
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /
              port: 3000
            initialDelaySeconds: 30
            periodSeconds: 30
      volumes:
        - name: secrets-store
          csi:
            driver: secrets-store.csi.k8s.io
            readOnly: true
            volumeAttributes:
              secretProviderClass: visign-kv-secrets
```

### 3E. Web Service (`k8s-specifications/visign-web-service.yaml`)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: visign-web
  namespace: visign
  labels:
    app: visign-web
spec:
  selector:
    app: visign-web
  ports:
    - port: 3000
      targetPort: 3000
      protocol: TCP
  type: ClusterIP
```

### 3F. Gateway + HTTPRoute (`k8s-specifications/httproute.yaml`)

Replaces nginx Ingress. AGC uses the Kubernetes **Gateway API** instead of the legacy `networking.k8s.io/v1 Ingress`.

- `Gateway` → references the AGC resource (created in Azure Portal) and the TLS cert Secret auto-managed by cert-manager.
- `HTTPRoute (http)` → 301 redirects all HTTP → HTTPS.
- `HTTPRoute (https)` → routes traffic to services.

cert-manager automatically obtains and renews the Let's Encrypt cert via Cloudflare DNS-01 challenge
and writes it into the `visign-tls` Secret that the Gateway references (see Stage 6A-6B).

```yaml
---
# Gateway — references AGC and the TLS cert Secret
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: visign-gateway
  namespace: visign
  annotations:
    alb.networking.azure.io/alb-namespace: azure-alb-system
    alb.networking.azure.io/alb-name: visign-agc
spec:
  gatewayClassName: azure-alb-external
  listeners:
    - name: http
      port: 80
      protocol: HTTP
      allowedRoutes:
        namespaces:
          from: Same
    - name: https
      port: 443
      protocol: HTTPS
      allowedRoutes:
        namespaces:
          from: Same
      tls:
        mode: Terminate
        certificateRefs:
          - name: visign-tls       # written by cert-manager
            namespace: visign
---
# HTTP → HTTPS redirect
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: visign-http-redirect
  namespace: visign
spec:
  parentRefs:
    - name: visign-gateway
      sectionName: http
  rules:
    - filters:
        - type: RequestRedirect
          requestRedirect:
            scheme: https
            statusCode: 301
---
# HTTPS routes
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: visign-https-routes
  namespace: visign
spec:
  parentRefs:
    - name: visign-gateway
      sectionName: https
  hostnames:
    - "lyhua.dpdns.org"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api/ai
        - path:
            type: PathPrefix
            value: /openapi.json
        - path:
            type: PathPrefix
            value: /docs
        - path:
            type: PathPrefix
            value: /redoc
      backendRefs:
        - name: visign-ai
          port: 8000
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: visign-web
          port: 3000
```

### 3H. SecretProviderClass Manifest (`k8s-specifications/secrets-provider.yaml`)

Define Key Vault -> Kubernetes secret sync as a file.

The `__KV_NAME__` and `__TENANT_ID__` placeholders will be replaced in **Stage 4A** using
the Bicep output values. Leave them as-is for now.

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: visign-kv-secrets
  namespace: visign
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"
    userAssignedIdentityID: "__CSI_CLIENT_ID__"    # Replace in Stage 4A
    keyvaultName: "__KV_NAME__"   # Replace with your KV name
    cloudName: ""
    objects: |
      array:
        - |
          objectName: DATABASE-URL
          objectType: secret
        - |
          objectName: CLERK-PUBLISHABLE-KEY
          objectType: secret
        - |
          objectName: CLERK-SECRET-KEY
          objectType: secret
    tenantId: "__TENANT_ID__"      # Replace with your tenant ID
  secretObjects:
    - secretName: visign-secrets
      type: Opaque
      data:
        - objectName: DATABASE-URL
          key: DATABASE_URL
        - objectName: CLERK-PUBLISHABLE-KEY
          key: NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY
        - objectName: CLERK-SECRET-KEY
          key: CLERK_SECRET_KEY
```

### 3I. CSI Driver RBAC (`k8s-specifications/cluster-role.yaml`)

The CSI Secrets Store driver needs permission to create/patch Kubernetes Secrets
in the `visign` namespace. Without this, the volume mounts from Key Vault succeed
but the `visign-secrets` K8s Secret (referenced by `secretKeyRef` in the web deployment)
is never created.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: csi-secrets-store-sync
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["create", "delete", "get", "list", "patch", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: csi-secrets-store-sync-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: csi-secrets-store-sync
subjects:
  - kind: ServiceAccount
    name: secrets-store-csi-driver
    namespace: kube-system
```

---

## Stage 4: Key Vault Runtime Secrets

### 4A. Grant yourself Key Vault access & patch `secrets-provider.yaml`

Bicep created your Key Vault with RBAC mode, but only granted AKS access — not **you**.
You need to give yourself write access first, then tell K8s which identity and
vault to use.

```bash
# 1. Get Key Vault name from Bicep output
KV_NAME=$(az deployment group show --resource-group visign-rg --name deploy-visign-platform \
  --query properties.outputs.keyVaultName.value -o tsv)
echo "Key Vault name: $KV_NAME"
KV_SCOPE="/subscriptions/$(az account show --query id -o tsv)/resourceGroups/visign-rg/providers/Microsoft.KeyVault/vaults/$KV_NAME"

# 2. Grant yourself "Key Vault Secrets Officer" so you can write secrets
USER_OID=$(az ad signed-in-user show --query id -o tsv)
az role assignment create \
  --role "Key Vault Secrets Officer" \
  --assignee "$USER_OID" \
  --scope "$KV_SCOPE"
# Wait ~30-60 seconds for RBAC propagation before the next step

# 3. Get the CSI Secrets Provider addon identity clientId
#    (AKS has multiple identities — the CSI driver needs to know WHICH one to use)
CSI_CLIENT_ID=$(az aks show --resource-group visign-rg --name visign-aks \
  --query addonProfiles.azureKeyvaultSecretsProvider.identity.clientId -o tsv)
echo "CSI Identity Client ID: $CSI_CLIENT_ID"

# 4. Grant the CSI identity "Key Vault Secrets User" so it can READ secrets
#    (Bicep only granted the kubelet identity, but the CSI addon has its own identity)
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee "$CSI_CLIENT_ID" \
  --scope "$KV_SCOPE"

# 5. Get your Azure tenant ID
TENANT_ID=$(az account show --query tenantId -o tsv)
echo "Tenant ID: $TENANT_ID"

# 6. Replace ALL placeholders in secrets-provider.yaml
sed -i "s|__KV_NAME__|$KV_NAME|g" k8s-specifications/secrets-provider.yaml
sed -i "s|__TENANT_ID__|$TENANT_ID|g" k8s-specifications/secrets-provider.yaml
sed -i "s|__CSI_CLIENT_ID__|$CSI_CLIENT_ID|g" k8s-specifications/secrets-provider.yaml

# 7. Verify the file looks correct
cat k8s-specifications/secrets-provider.yaml

# 8. Commit and push (ArgoCD will deploy it)
git add k8s-specifications/secrets-provider.yaml
git commit -m "chore: set Key Vault name, tenant ID, and CSI identity in secrets-provider"
git push
```

### 4B. Store Secrets in Key Vault

Store only runtime keys currently consumed by the existing `k8s-specifications/visign-web-deployment.yaml` manifest.

Credential mapping for runtime path:

| Key Vault secret name | `secretObjects.data.key` in `secrets-provider.yaml` | Consumed in web deployment env |
|---|---|---|
| `DATABASE-URL` | `DATABASE_URL` | `DATABASE_URL` |
| `CLERK-PUBLISHABLE-KEY` | `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` | `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` |
| `CLERK-SECRET-KEY` | `CLERK_SECRET_KEY` | `CLERK_SECRET_KEY` |

```bash
# Store your secrets (KV_NAME variable was set in step 4A above)
az keyvault secret set --vault-name "$KV_NAME" --name "DATABASE-URL" \
  --value "postgresql://user:pass@host/dbname"

az keyvault secret set --vault-name "$KV_NAME" --name "CLERK-PUBLISHABLE-KEY" \
  --value "pk_test_xxxx"

az keyvault secret set --vault-name "$KV_NAME" --name "CLERK-SECRET-KEY" \
  --value "sk_test_xxxx"
```

---

## Stage 5: CI with GitHub Actions

### 5A. Set Up GitHub Secrets

Set these CI build secrets in GitHub Actions.

Go to your GitHub repo → Settings → Secrets and variables → Actions, add:

| Secret Name | Value |
|---|---|
| `ACR_LOGIN_SERVER` | e.g. `visignacrabc123.azurecr.io` |
| `ACR_USERNAME` | From ACR Access Keys |
| `ACR_PASSWORD` | From ACR Access Keys |
| `DATABASE_URL` | Production Neon/Postgres connection string |
| `OPENAI_API_KEY` | OpenAI API key for feedback generation |
| `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` | Clerk publishable key |
| `CLERK_SECRET_KEY` | Clerk secret key |
| `TORCH_COMPUTE` | `cpu` for CPU node pools, `gpu` for GPU node pools |

### 5B. CI Workflow for AI Service (`.github/workflows/ci-cd-ai.yml`)

```yaml
name: CI - Visign AI Service

on:
  push:
    branches: [main]
    paths:
      - "ai-model/**"
      - ".github/workflows/ci-cd-ai.yml"
  pull_request:
    branches: [main]
    paths:
      - "ai-model/**"
      - ".github/workflows/ci-cd-ai.yml"

env:
  IMAGE_NAME: visign-ai

permissions:
  contents: write

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    if: github.event_name == 'push'
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Write build env file
        run: |
          cat > .env <<EOF
          TORCH_COMPUTE=${{ secrets.TORCH_COMPUTE }}
          DATABASE_URL=dummy-for-ai-build
          OPENAI_API_KEY=dummy-for-ai-build
          NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=dummy-for-ai-build
          EOF

      - name: Build AI image with Compose
        run: docker compose build fastapi

      - name: Login to ACR
        uses: azure/docker-login@v1
        with:
          login-server: ${{ secrets.ACR_LOGIN_SERVER }}
          username: ${{ secrets.ACR_USERNAME }}
          password: ${{ secrets.ACR_PASSWORD }}

      - name: Tag and push image
        run: |
          LOCAL_IMAGE="visign-llmates-fastapi:latest"
          docker image inspect "$LOCAL_IMAGE" > /dev/null
          docker tag "$LOCAL_IMAGE" "${{ secrets.ACR_LOGIN_SERVER }}/${{ env.IMAGE_NAME }}:${{ github.sha }}"
          docker tag "$LOCAL_IMAGE" "${{ secrets.ACR_LOGIN_SERVER }}/${{ env.IMAGE_NAME }}:latest"
          docker push "${{ secrets.ACR_LOGIN_SERVER }}/${{ env.IMAGE_NAME }}:${{ github.sha }}"
          docker push "${{ secrets.ACR_LOGIN_SERVER }}/${{ env.IMAGE_NAME }}:latest"

      - name: Update AI manifest tag (GitOps)
        if: github.ref == 'refs/heads/main'
        run: |
          set -euo pipefail
          sed -i "s|:latest|:${{ github.sha }}|g" k8s-specifications/visign-ai-deployment.yaml
          sed -i "s|__ACR_LOGIN_SERVER__|${{ secrets.ACR_LOGIN_SERVER }}|g" k8s-specifications/visign-ai-deployment.yaml
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add k8s-specifications/visign-ai-deployment.yaml
          git commit -m "ci(ai): update visign-ai image tag to ${{ github.sha }}" || exit 0

          for attempt in 1 2 3; do
            if git push origin HEAD:main; then
              exit 0
            fi

            echo "Push rejected (attempt ${attempt}), rebasing onto origin/main and retrying..."
            git pull --rebase origin main
          done

          echo "Failed to push manifest update after 3 attempts"
          exit 1
```

### 5C. CI Workflow for Web Service (`.github/workflows/ci-cd-web.yml`)

```yaml
name: CI - Visign Web Service

on:
  push:
    branches: [main]
    paths:
      - "visign/**"
      - ".github/workflows/ci-cd-web.yml"
  pull_request:
    branches: [main]
    paths:
      - "visign/**"
      - ".github/workflows/ci-cd-web.yml"

env:
  IMAGE_NAME: visign-web

permissions:
  contents: write

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    if: github.event_name == 'push'
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Write build env file
        run: |
          cat > .env <<EOF
          TORCH_COMPUTE=cpu
          DATABASE_URL=${{ secrets.DATABASE_URL }}
          OPENAI_API_KEY=${{ secrets.OPENAI_API_KEY }}
          NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=${{ secrets.NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY }}
          CLERK_SECRET_KEY=${{ secrets.CLERK_SECRET_KEY }}
          EOF

      - name: Build web image with Compose
        run: docker compose build nextjs

      - name: Login to ACR
        uses: azure/docker-login@v1
        with:
          login-server: ${{ secrets.ACR_LOGIN_SERVER }}
          username: ${{ secrets.ACR_USERNAME }}
          password: ${{ secrets.ACR_PASSWORD }}

      - name: Tag and push image
        run: |
          LOCAL_IMAGE="visign-llmates-nextjs:latest"
          docker image inspect "$LOCAL_IMAGE" > /dev/null
          docker tag "$LOCAL_IMAGE" "${{ secrets.ACR_LOGIN_SERVER }}/${{ env.IMAGE_NAME }}:${{ github.sha }}"
          docker tag "$LOCAL_IMAGE" "${{ secrets.ACR_LOGIN_SERVER }}/${{ env.IMAGE_NAME }}:latest"
          docker push "${{ secrets.ACR_LOGIN_SERVER }}/${{ env.IMAGE_NAME }}:${{ github.sha }}"
          docker push "${{ secrets.ACR_LOGIN_SERVER }}/${{ env.IMAGE_NAME }}:latest"

      - name: Update web manifest tag (GitOps)
        if: github.ref == 'refs/heads/main'
        run: |
          set -euo pipefail
          sed -i "s|:latest|:${{ github.sha }}|g" k8s-specifications/visign-web-deployment.yaml
          sed -i "s|__ACR_LOGIN_SERVER__|${{ secrets.ACR_LOGIN_SERVER }}|g" k8s-specifications/visign-web-deployment.yaml
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add k8s-specifications/visign-web-deployment.yaml
          git commit -m "ci(web): update visign-web image tag to ${{ github.sha }}" || exit 0

          for attempt in 1 2 3; do
            if git push origin HEAD:main; then
              exit 0
            fi

            echo "Push rejected (attempt ${attempt}), rebasing onto origin/main and retrying..."
            git pull --rebase origin main
          done

          echo "Failed to push manifest update after 3 attempts"
          exit 1
```

---

## Stage 6: Pull-based CD with ArgoCD

### 6A. Create AGC in Azure Portal + Install ALB Controller

Azure Application Gateway for Containers (AGC) replaces nginx-ingress.
TLS certificates are still handled by cert-manager (see 6B) — AGC just reads the resulting K8s Secret.

**Prerequisites in Azure Portal (do once):**
1. Create an **Application Gateway for Containers** resource:
   - Basics: Name = `visign-agc`, Resource group = `visign-rg`, same region as AKS
   - Frontends: add a frontend (public IP auto-allocated — note this IP for DNS)
   - Associations: link to the AKS VNet + subnet
   - Skip Security policies and Tags
2. The AGC name (`visign-agc`) must match `alb.networking.azure.io/alb-name` in `httproute.yaml`

**Install Gateway API CRDs + ALB Controller into AKS:**

```bash
# Install Gateway API CRDs (required before ALB controller)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

# Add ALB controller Helm repo
helm repo add aks-alb-controller https://azure.github.io/application-gateway-for-containers/helm
helm repo update

# Install ALB controller
helm install alb-controller aks-alb-controller/alb-controller \
  --namespace azure-alb-system --create-namespace \
  --set albController.namespace=azure-alb-system \
  --set albController.podIdentity.clientID=$(az identity show \
    --resource-group visign-rg \
    --name alb-identity \
    --query clientId -o tsv)

# Verify
kubectl get pods -n azure-alb-system
```

**If ingress-nginx was previously installed, remove it:**
```bash
helm uninstall ingress-nginx -n ingress-nginx
kubectl delete namespace ingress-nginx
```

### 6B. Install cert-manager + Cloudflare DNS-01 Issuer

cert-manager is the Kubernetes equivalent of certbot — it automatically obtains and renews
a Let's Encrypt certificate via the **Cloudflare DNS-01 challenge**. No HTTP challenge needed,
no need for a working ingress first. cert-manager writes the cert into the `visign-tls` K8s Secret
that your AGC Gateway reads.

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true
```

**Create a Cloudflare API token** (cert-manager needs it to create DNS TXT records):
1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com/profile/api-tokens) → **API Tokens** → **Create Token**
2. Use template: **Edit zone DNS** → scope to your zone (`lyhua.dpdns.org`) → **Create Token**
3. Copy the token value

**Store the token as a K8s Secret:**
```bash
kubectl create secret generic cloudflare-api-token \
  --from-literal=api-token="<YOUR_CLOUDFLARE_API_TOKEN>" \
  --namespace cert-manager
```

**Apply the ClusterIssuer** (`k8s-specifications/cluster-issuer-dns.yaml` — already in repo):
```bash
kubectl apply -f k8s-specifications/cluster-issuer-dns.yaml
```

The `cluster-issuer-dns.yaml` tells cert-manager to use Let's Encrypt production + Cloudflare DNS-01:
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-dns
spec:
  acme:
    email: lyhuavanly@gmail.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-dns
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token
              key: api-token
```

**Request the certificate** (cert-manager will auto-create the `visign-tls` Secret):
```bash
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: visign-tls
  namespace: visign
spec:
  secretName: visign-tls
  issuerRef:
    name: letsencrypt-dns
    kind: ClusterIssuer
  dnsNames:
    - lyhua.dpdns.org
EOF

# Watch until Ready = True (takes 1-3 minutes)
kubectl get certificate -n visign visign-tls -w
```

Once `Ready = True`, the `visign-tls` Secret exists → AGC Gateway can terminate TLS.
Cert-manager auto-renews every ~60 days.

**Cloudflare DNS setup:**
- In Cloudflare DNS, add an **A record**: name `@`, value = AGC frontend public IP, **Proxied** ✅
- SSL/TLS mode: **Full** (not Strict, since Let's Encrypt is the cert on AGC side)

### 6C. Install ArgoCD into AKS

Recommended path:

- Follow the ArgoCD installation flow documented in [README(3).md](README(3).md#L367) Step 3 and Step 4.
- Use this guide's commands below as the direct/CLI equivalent.

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### 6D. Log in to ArgoCD

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

In another terminal:

```bash
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
argocd login localhost:8080 --username admin --password "$ARGOCD_PASSWORD" --insecure
```

Open UI: `https://localhost:8080`

### 6E. Create ArgoCD application (`k8s-specifications/argocd-application.yaml`)

Recommended:

- Create the ArgoCD application from ArgoCD UI as shown in [README(3).md](README(3).md#L475).

Not recommended (but supported):

- Create application by committing and applying a raw Argo Application YAML.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: visign
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<your-org>/<your-repo>.git
    targetRevision: main
    path: k8s-specifications
  destination:
    server: https://kubernetes.default.svc
    namespace: visign
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### 6F. Bootstrap application and verify

```bash
kubectl apply -f k8s-specifications/argocd-application.yaml
kubectl -n argocd get applications.argoproj.io
```

From this point onward:

1. GitHub Actions does CI only (build + push + manifest tag commit).
2. ArgoCD does CD only (pull + reconcile into AKS).

### 6G. HTTPS Verification Runbook

```bash
# 1) Gateway and HTTPRoute status
kubectl get gateway -n visign visign-gateway
kubectl get httproute -n visign

# 2) cert-manager certificate status
kubectl get certificate -n visign visign-tls

# 3) AGC frontend public IP
kubectl get gateway -n visign visign-gateway -o jsonpath='{.status.addresses[*].value}'

# 4) DNS resolves to AGC IP
nslookup lyhua.dpdns.org

# 5) HTTPS reachability
# Windows
Test-NetConnection lyhua.dpdns.org -Port 443
# Linux/macOS
curl -v --connect-timeout 10 https://lyhua.dpdns.org
```

Interpretation:
- Gateway has no address → ALB controller not reconciled. Check: `kubectl logs -n azure-alb-system -l app=alb-controller`
- Certificate `Ready = False` → check: `kubectl describe certificate -n visign visign-tls` and `kubectl get challenges -n visign`
- DNS wrong → update Cloudflare A record to AGC IP
- HTTPS fails but DNS correct → verify `visign-tls` Secret exists: `kubectl get secret -n visign visign-tls`

---

## Stage 7: Prometheus + Grafana Monitoring

### 7A. Add Prometheus Metrics to FastAPI (CODE CHANGES)

Add the required library and instrumentation code.

**Add to `ai-model/requirements.txt`:**
```
prometheus-fastapi-instrumentator>=6.0.0
```

**Add to `ai-model/app.py` (just 2 lines):**

```python
# At the top of app.py, after creating the FastAPI app:
from prometheus_fastapi_instrumentator import Instrumentator

app = FastAPI(title="sudo-visign Web App")

# Add this line right after app creation:
Instrumentator().instrument(app).expose(app)
```

This creates a `/metrics` endpoint that Prometheus scrapes. It tracks:
- Request count, latency, size per endpoint
- HTTP status codes
- In-progress requests

### 7B. Add Prometheus Annotations to K8s Deployments

Add these annotations to **both** deployment pod templates so Prometheus auto-discovers them:

In `k8s-specifications/visign-ai-deployment.yaml`, add under `spec.template.metadata`:
```yaml
    metadata:
      labels:
        app: visign-ai
      annotations:                          # ← ADD
        prometheus.io/scrape: "true"        # ← ADD
        prometheus.io/port: "8000"          # ← ADD
        prometheus.io/path: "/metrics"      # ← ADD
```

For `visign-web`, Next.js doesn't natively expose Prometheus metrics, but Prometheus will still monitor the pods via kube-state-metrics and node-exporter (CPU, memory, restarts, etc.)

### 7C. Install Prometheus + Grafana via Helm

Recommended (private access, no public Grafana, no custom values file required):

```bash
# Add Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack (includes Prometheus + Grafana + AlertManager)
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace

# Wait for everything to be ready
kubectl get pods -n monitoring --watch

# Access Grafana privately (like ArgoCD)
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80

# In another terminal, fetch generated credentials from secret
GRAFANA_USER=$(kubectl -n monitoring get secret monitoring-grafana -o jsonpath='{.data.admin-user}' | base64 -d)
GRAFANA_PASSWORD=$(kubectl -n monitoring get secret monitoring-grafana -o jsonpath='{.data.admin-password}' | base64 -d)
echo "$GRAFANA_USER"
echo "$GRAFANA_PASSWORD"
```

Open: `http://localhost:3000`

Security guidance:

- Do not expose Grafana as `LoadBalancer` in normal setups.
- Use port-forward access for admin work.
- Rotate the admin password immediately after first login.

If Grafana was previously exposed publicly, force it back to private service type:

```bash
kubectl patch svc -n monitoring monitoring-grafana -p '{"spec":{"type":"ClusterIP"}}'
```

Not recommended (advanced/manual):

- Installing with custom YAML values for Grafana exposure/password unless you have a specific audited reason.
- If you still need custom settings, keep them in `monitoring/prometheus-values.yaml` and keep Grafana service type as `ClusterIP`.

### 7D. Grafana Dashboard Setup

Once logged into Grafana:

1. **Go to** Dashboards → Import
2. **Import Dashboard ID `315`** (Kubernetes cluster monitoring by CoreOS) — gives you node/pod/namespace metrics
3. **Import Dashboard ID `6417`** (Kubernetes Cluster) — another comprehensive view

For **custom Visign metrics**, create a new dashboard:
- Panel 1: `rate(http_requests_total{app="visign-ai"}[5m])` → Request Rate
- Panel 2: `histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{app="visign-ai"}[5m]))` → P95 Latency
- Panel 3: `sum(up{namespace="visign"})` → Running pods count
- Panel 4: `container_memory_usage_bytes{namespace="visign"}` → Memory usage

### 7E. Basic Alert Rules

Grafana has built-in alerts. Set up these basic ones:

- **Pod CrashLooping:** Alert when `kube_pod_container_status_restarts_total` increases rapidly
- **High CPU:** Alert when pod CPU usage > 80% for 5 minutes
- **Pod Not Ready:** Alert when `kube_pod_status_ready{namespace="visign"}` = 0

---

## Appendix A (Optional): HTTPS/TLS Setup

Use this appendix only if you want public HTTPS and certificate automation.

### A.1 Ingress TLS annotations and TLS block

Update `k8s-specifications/ingress.yaml` to include:

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    acme.cert-manager.io/http01-edit-in-place: "true"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  tls:
    - hosts:
        - app.yourdomain.com
      secretName: visign-tls
```

Use a real domain (for example `app.yourdomain.com`) that points to your ingress public IP.
Avoid using `nip.io` or raw IP for production TLS issuance.

### A.2 HTTPS preflight checks

Run these checks in order. If any step fails, stop and fix before waiting for cert-manager retries.

```bash
# 1) Confirm ingress has a public IP
kubectl get svc -n ingress-nginx ingress-nginx-controller -o wide

# 2) Confirm your host resolves to that same IP
nslookup app.yourdomain.com

# 3) Confirm public HTTP reachability from an external network
# (not from inside cluster)
curl -I http://app.yourdomain.com

# 4) Confirm cert-manager stack is healthy
kubectl get pods -n cert-manager
kubectl get clusterissuer letsencrypt-prod
```

If step 3 times out, do not continue with HTTP-01. Move to DNS-01 in section A.4.

### A.3 HTTP-01 ClusterIssuer manifest

`k8s-specifications/cluster-issuer.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: your-email@example.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: nginx
```

### A.4 DNS-01 ClusterIssuer fallback (Cloudflare)

Use DNS-01 when Let's Encrypt cannot connect to your ingress public IP on port 80.
This avoids network-path dependency on HTTP reachability.

`k8s-specifications/cluster-issuer-dns.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-dns
spec:
  acme:
    email: your-email@example.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-dns
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token
              key: api-token
```

Create Cloudflare token secret:

```bash
kubectl create secret generic cloudflare-api-token \
  -n cert-manager \
  --from-literal=api-token='<CLOUDFLARE_API_TOKEN>'

kubectl apply -f k8s-specifications/cluster-issuer-dns.yaml
```

Then update ingress annotation to use DNS issuer:

```yaml
cert-manager.io/cluster-issuer: "letsencrypt-dns"
```

Re-issue certificate:

```bash
kubectl delete certificate -n visign visign-tls
kubectl delete secret -n visign visign-tls --ignore-not-found
kubectl apply -f k8s-specifications/ingress.yaml
kubectl get certificate,order,challenge -n visign -w
```

Cloudflare API token usage:

- Stored as Kubernetes Secret `cloudflare-api-token` in namespace `cert-manager`.
- Read by cert-manager only during ACME DNS-01 challenge.
- Not read by `visign-web` or `visign-ai` application pods.

---

## Cost Saving

```bash
# Stop AKS cluster (deallocates node compute)
az aks stop --resource-group visign-rg --name visign-aks

# Resume later
az aks start --resource-group visign-rg --name visign-aks
az aks get-credentials --resource-group visign-rg --name visign-aks --overwrite-existing
```

---

## Quick Reference: Order of Operations

```
Stage 0: Install tooling and authenticate Azure CLI.
Stage 1: Build and verify local Docker images with Docker Compose.
Stage 2: Deploy infrastructure with infra/main.subscription.bicep + infra/main.subscription.bicepparam.
Stage 3: Author and commit all Kubernetes manifests in k8s-specifications/.
Stage 4: Store Key Vault runtime secrets.
Stage 5: Set GitHub CI secrets and run CI workflows.
Stage 6: Bootstrap ArgoCD and let ArgoCD reconcile.
Stage 7: Install kube-prometheus-stack and configure Grafana dashboards/alerts.
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `ImagePullBackOff` | ACR not attached to AKS. Run: `az aks update -n visign-aks -g visign-rg --attach-acr <acr-name>` |
| Pod stuck `Pending` | Not enough resources. Check: `kubectl describe pod <name> -n visign` |
| Ingress no external IP | Check events first: `kubectl describe svc -n ingress-nginx ingress-nginx-controller`. If you see `PublicIPCountLimitReached`, free unused Public IPs in this region or request quota increase, then wait for reconcile. |
| Grafana not loading | Check pod: `kubectl logs -n monitoring -l app.kubernetes.io/name=grafana` |
| Bicep deployment fails | Check subscription deployment errors: `az deployment sub list --query "[].{name:name,state:properties.provisioningState}" -o table` then `az deployment sub show --name <deployment-name> --query properties.error` |
| CI pipeline fails | Check GitHub Actions logs and verify ACR/env secrets are set correctly |
| ArgoCD app not syncing | Check: `kubectl -n argocd get applications.argoproj.io` and `argocd app get visign` |
| `required variable TORCH_COMPUTE is missing a value` in `docker compose build` | Add `TORCH_COMPUTE=cpu` or `TORCH_COMPUTE=gpu` to repo-root `.env` |
| `docker-credential-desktop` not found | Remove `"credsStore": "desktop"` from `~/.docker/config.json`, then run `docker login` |
| `next: not found` during Docker build | In Dockerfile use `npm ci --include=dev` in build stage, then rebuild with `--no-cache` |
| AI build times out downloading CUDA wheels | Install CPU-only torch from `https://download.pytorch.org/whl/cpu` and use runtime-only requirements |
| `No database connection string was provided to neon()` during `npm run build` | Ensure `DATABASE_URL` exists in repo-root `.env` before running `docker compose build` |
| `/docs` shows Swagger but fails `Not Found /openapi.json` | In ingress, route `/openapi.json` to `visign-ai:8000` and keep `/api` routed to `visign-web:3000` |
| `Error accepting authorization ... Timeout during connect (likely firewall problem)` from cert-manager | HTTP-01 cannot reach your ingress on port 80. Run **Appendix A.2** preflight checks. If public HTTP is not reachable, switch to **Appendix A.4 DNS-01** with a real domain and re-issue the certificate. |
