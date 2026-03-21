# DevOps Project: Deploy Visign (Next.js + FastAPI AI) on Azure AKS

> Complete step-by-step guide: Docker → Bicep IaC → K8s Manifests → GitHub Actions CI/CD → Prometheus+Grafana Monitoring

---

## TABLE OF CONTENTS

**Stage 0:** Prerequisites & Repository Setup  
**Stage 1:** Docker Images (visign-web, visign-ai)  
**Stage 2:** Bicep IaC — Provision Azure Infrastructure (AKS, ACR, Key Vault)  
**Stage 3:** Kubernetes Manifests (Deployment/Service/Ingress + 2 Replicas across 2 AZs)  
**Stage 4:** CI/CD with GitHub Actions (Build → Push ACR → Deploy AKS)  
**Stage 5:** Prometheus + Grafana Monitoring  
**Stage 6:** Key Vault Secrets Integration  

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
│GitHub Actions│ ──deploy──────────────────────►│  │  (FastAPI)      │  │
│   CI/CD      │                                │  ├─────────────────┤  │
└──────────────┘                                │  │  Prometheus     │  │
                                                │  │  Grafana        │  │
       ┌────────────┐                           │  ├─────────────────┤  │
       │ Key Vault  │◄─────secrets──────────────│  │  Ingress (nginx)│  │
       └────────────┘                           │  └─────────────────┘  │
                                                │   Zone 1  │  Zone 2   │
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
├── k8s/                         # 🆕 Kubernetes manifests
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
    kubernetesVersion: '1.29'
    agentPoolProfiles: [
      {
        name: 'agentpool'
        count: nodeCount
        vmSize: nodeVMSize
        osType: 'Linux'
        mode: 'System'
        availabilityZones: [
          '1'
          '2'
        ]
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

### 2F. Deploy Infrastructure

```bash
# 1. Create resource group
az group create --name visign-rg --location southeastasia

# 2. Deploy all infrastructure with Bicep
az deployment group create \
  --resource-group visign-rg \
  --template-file infra/main.bicep \
  --parameters infra/parameters.json

# 3. Get outputs (save these — you'll need them everywhere)
az deployment group show \
  --resource-group visign-rg \
  --name main \
  --query properties.outputs

# 4. Connect to AKS
az aks get-credentials --resource-group visign-rg --name visign-aks --overwrite-existing

# 5. Verify
kubectl get nodes
# You should see 2 nodes across 2 availability zones
```

> **💡 TIP:** Run `kubectl describe nodes | grep -e "Name:" -e "topology.kubernetes.io/zone"` to verify nodes are in different AZs.

---

## Stage 3: Kubernetes Manifests

### 3A. Namespace (`k8s/namespace.yaml`)

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: visign
  labels:
    app.kubernetes.io/part-of: visign
```

### 3B. AI Service Deployment (`k8s/visign-ai-deployment.yaml`)

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

### 3C. AI Service (`k8s/visign-ai-service.yaml`)

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

### 3D. Web Deployment (`k8s/visign-web-deployment.yaml`)

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
```

### 3E. Web Service (`k8s/visign-web-service.yaml`)

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

### 3F. Ingress Controller Setup + Ingress (`k8s/ingress.yaml`)

Use the Kubernetes-standard portable path: `ingress-nginx` + `cert-manager`.

First install the NGINX Ingress Controller:

```bash
# Install NGINX Ingress Controller via Helm
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.replicaCount=2
```

Then install cert-manager (for TLS automation with Let's Encrypt):

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true
```

Create a ClusterIssuer (one-time setup):

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

Apply it:

```bash
kubectl apply -f k8s/cluster-issuer.yaml
```

Then the Ingress resource:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: visign-ingress
  namespace: visign
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "120"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - visign.example.com
      secretName: visign-tls
  rules:
    - host: visign.example.com
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: visign-ai
                port:
                  number: 8000
          - path: /docs
            pathType: Prefix
            backend:
              service:
                name: visign-ai
                port:
                  number: 8000
          - path: /
            pathType: Prefix
            backend:
              service:
                name: visign-web
                port:
                  number: 3000
```

### 3G. Create K8s Secrets (manual, for first time)

```bash
# Create the namespace first
kubectl apply -f k8s/namespace.yaml

# Create secrets manually (these will later be managed by Key Vault)
kubectl create secret generic visign-secrets \
  --namespace visign \
  --from-literal=DATABASE_URL="postgresql://user:pass@host/db" \
  --from-literal=NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY="pk_test_xxx" \
  --from-literal=CLERK_SECRET_KEY="sk_test_xxx"
```

### 3H. Deploy Everything

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/visign-ai-deployment.yaml
kubectl apply -f k8s/visign-ai-service.yaml
kubectl apply -f k8s/visign-web-deployment.yaml
kubectl apply -f k8s/visign-web-service.yaml
kubectl apply -f k8s/ingress.yaml

# Verify
kubectl get all -n visign
kubectl get ingress -n visign
```

---

## Stage 4: CI/CD with GitHub Actions

### 4A. Set Up GitHub Secrets

Go to your GitHub repo → Settings → Secrets and variables → Actions, add:

| Secret Name | Value |
|---|---|
| `AZURE_CREDENTIALS` | Output of `az ad sp create-for-rbac --name visign-cicd --role contributor --scopes /subscriptions/<SUB_ID>/resourceGroups/visign-rg --sdk-auth` |
| `ACR_LOGIN_SERVER` | e.g. `visignacrabc123.azurecr.io` |
| `ACR_USERNAME` | From ACR Access Keys |
| `ACR_PASSWORD` | From ACR Access Keys |
| `AKS_RESOURCE_GROUP` | `visign-rg` |
| `AKS_CLUSTER_NAME` | `visign-aks` |
| `DATABASE_URL` | Production Neon/Postgres connection string |
| `OPENAI_API_KEY` | OpenAI API key for feedback generation |
| `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` | Clerk publishable key |
| `TORCH_COMPUTE` | `cpu` for CPU node pools, `gpu` for GPU node pools |

Disclaimer: You may store non-sensitive config in Repository Variables, but this guide keeps all required build values in Secrets for a single, consistent setup path.

### 4B. CI/CD for AI Service (`.github/workflows/ci-cd-ai.yml`)

```yaml
name: CI/CD - Visign AI Service

on:
  push:
    branches: [main]
    paths:
      - 'ai-model/**'
  pull_request:
    branches: [main]
    paths:
      - 'ai-model/**'

env:
  IMAGE_NAME: visign-ai

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    if: github.event_name == 'push'
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Login to ACR
        uses: azure/docker-login@v1
        with:
          login-server: ${{ secrets.ACR_LOGIN_SERVER }}
          username: ${{ secrets.ACR_USERNAME }}
          password: ${{ secrets.ACR_PASSWORD }}

      - name: Build and push Docker image
        run: |
          cat > .env <<EOF
          TORCH_COMPUTE=${{ secrets.TORCH_COMPUTE }}
          DATABASE_URL=dummy-for-ai-build
          OPENAI_API_KEY=dummy-for-ai-build
          NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=dummy-for-ai-build
          EOF

          docker compose build fastapi
          docker tag visign-llmates-fastapi:latest ${{ secrets.ACR_LOGIN_SERVER }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
          docker tag visign-llmates-fastapi:latest ${{ secrets.ACR_LOGIN_SERVER }}/${{ env.IMAGE_NAME }}:latest
          docker push ${{ secrets.ACR_LOGIN_SERVER }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
          docker push ${{ secrets.ACR_LOGIN_SERVER }}/${{ env.IMAGE_NAME }}:latest

  deploy:
    runs-on: ubuntu-latest
    needs: build-and-push
    if: github.ref == 'refs/heads/main'
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Azure Login
        uses: azure/login@v2
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Set AKS context
        uses: azure/aks-set-context@v3
        with:
          resource-group: ${{ secrets.AKS_RESOURCE_GROUP }}
          cluster-name: ${{ secrets.AKS_CLUSTER_NAME }}

      - name: Deploy to AKS
        run: |
          sed -i "s|__ACR_LOGIN_SERVER__|${{ secrets.ACR_LOGIN_SERVER }}|g" k8s/visign-ai-deployment.yaml
          sed -i "s|:latest|:${{ github.sha }}|g" k8s/visign-ai-deployment.yaml
          kubectl apply -f k8s/namespace.yaml
          kubectl apply -f k8s/visign-ai-deployment.yaml
          kubectl apply -f k8s/visign-ai-service.yaml
          kubectl rollout status deployment/visign-ai -n visign --timeout=300s
```

### 4C. CI/CD for Web Service (`.github/workflows/ci-cd-web.yml`)

```yaml
name: CI/CD - Visign Web Service

on:
  push:
    branches: [main]
    paths:
      - 'visign/**'
  pull_request:
    branches: [main]
    paths:
      - 'visign/**'

env:
  IMAGE_NAME: visign-web

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    if: github.event_name == 'push'
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Login to ACR
        uses: azure/docker-login@v1
        with:
          login-server: ${{ secrets.ACR_LOGIN_SERVER }}
          username: ${{ secrets.ACR_USERNAME }}
          password: ${{ secrets.ACR_PASSWORD }}

      - name: Build and push Docker image
        run: |
          cat > .env <<EOF
          TORCH_COMPUTE=cpu
          DATABASE_URL=${{ secrets.DATABASE_URL }}
          OPENAI_API_KEY=${{ secrets.OPENAI_API_KEY }}
          NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=${{ secrets.NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY }}
          EOF

          docker compose build nextjs
          docker tag visign-llmates-nextjs:latest ${{ secrets.ACR_LOGIN_SERVER }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
          docker tag visign-llmates-nextjs:latest ${{ secrets.ACR_LOGIN_SERVER }}/${{ env.IMAGE_NAME }}:latest
          docker push ${{ secrets.ACR_LOGIN_SERVER }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
          docker push ${{ secrets.ACR_LOGIN_SERVER }}/${{ env.IMAGE_NAME }}:latest

  deploy:
    runs-on: ubuntu-latest
    needs: build-and-push
    if: github.ref == 'refs/heads/main'
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Azure Login
        uses: azure/login@v2
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Set AKS context
        uses: azure/aks-set-context@v3
        with:
          resource-group: ${{ secrets.AKS_RESOURCE_GROUP }}
          cluster-name: ${{ secrets.AKS_CLUSTER_NAME }}

      - name: Deploy to AKS
        run: |
          sed -i "s|__ACR_LOGIN_SERVER__|${{ secrets.ACR_LOGIN_SERVER }}|g" k8s/visign-web-deployment.yaml
          sed -i "s|:latest|:${{ github.sha }}|g" k8s/visign-web-deployment.yaml
          kubectl apply -f k8s/namespace.yaml
          kubectl apply -f k8s/visign-web-deployment.yaml
          kubectl apply -f k8s/visign-web-service.yaml
          kubectl apply -f k8s/ingress.yaml
          kubectl rollout status deployment/visign-web -n visign --timeout=300s
```

---

## Stage 5: Prometheus + Grafana Monitoring

### 5A. Add Prometheus Metrics to FastAPI (CODE CHANGES)

Yes, you DO need to add code. Install the library and add a few lines:

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

That's it! This automatically creates a `/metrics` endpoint that Prometheus scrapes. It tracks:
- Request count, latency, size per endpoint
- HTTP status codes
- In-progress requests

### 5B. Add Prometheus Annotations to K8s Deployments

Add these annotations to **both** deployment pod templates so Prometheus auto-discovers them:

In `k8s/visign-ai-deployment.yaml`, add under `spec.template.metadata`:
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

### 5C. Install Prometheus + Grafana via Helm

Create `monitoring/prometheus-values.yaml`:

```yaml
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    additionalScrapeConfigs:
      - job_name: 'visign-ai-pods'
        kubernetes_sd_configs:
          - role: pod
            namespaces:
              names:
                - visign
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
            action: keep
            regex: true
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
            action: replace
            target_label: __metrics_path__
            regex: (.+)
          - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
            action: replace
            regex: ([^:]+)(?::\d+)?;(\d+)
            replacement: $1:$2
            target_label: __address__
          - source_labels: [__meta_kubernetes_pod_label_app]
            action: replace
            target_label: app

grafana:
  adminPassword: "visign-admin-2024"
  service:
    type: LoadBalancer
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: 'default'
          orgId: 1
          folder: ''
          type: file
          disableDeletion: false
          editable: true
          options:
            path: /var/lib/grafana/dashboards/default

alertmanager:
  enabled: true
```

**Install:**

```bash
# Add Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack (includes Prometheus + Grafana + AlertManager)
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --values monitoring/prometheus-values.yaml \
  --set grafana.service.type=LoadBalancer

# Wait for everything to be ready
kubectl get pods -n monitoring --watch

# Get Grafana external IP
kubectl get svc -n monitoring monitoring-grafana
# Login: admin / visign-admin-2024
```

### 5D. Grafana Dashboard Setup

Once logged into Grafana:

1. **Go to** Dashboards → Import
2. **Import Dashboard ID `315`** (Kubernetes cluster monitoring by CoreOS) — gives you node/pod/namespace metrics
3. **Import Dashboard ID `6417`** (Kubernetes Cluster) — another comprehensive view

For **custom Visign metrics**, create a new dashboard:
- Panel 1: `rate(http_requests_total{app="visign-ai"}[5m])` → Request Rate
- Panel 2: `histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{app="visign-ai"}[5m]))` → P95 Latency
- Panel 3: `sum(up{namespace="visign"})` → Running pods count
- Panel 4: `container_memory_usage_bytes{namespace="visign"}` → Memory usage

### 5E. Basic Alert Rules

Grafana has built-in alerts. Set up these basic ones:

- **Pod CrashLooping:** Alert when `kube_pod_container_status_restarts_total` increases rapidly
- **High CPU:** Alert when pod CPU usage > 80% for 5 minutes
- **Pod Not Ready:** Alert when `kube_pod_status_ready{namespace="visign"}` = 0

---

## Stage 6: Key Vault Secrets Integration

### 6A. Store Secrets in Key Vault

```bash
# Get your Key Vault name from Bicep output
KV_NAME=$(az deployment group show --resource-group visign-rg --name main \
  --query properties.outputs.keyVaultName.value -o tsv)

# Store your secrets
az keyvault secret set --vault-name $KV_NAME --name "DATABASE-URL" \
  --value "postgresql://user:pass@host/dbname"

az keyvault secret set --vault-name $KV_NAME --name "CLERK-PUBLISHABLE-KEY" \
  --value "pk_test_xxxx"

az keyvault secret set --vault-name $KV_NAME --name "CLERK-SECRET-KEY" \
  --value "sk_test_xxxx"
```

### 6B. Create SecretProviderClass (`k8s/secrets-provider.yaml`)

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
    userAssignedIdentityID: ""    # Leave empty for system-assigned
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

Add this volume mount to the `visign-web` deployment:

```yaml
      volumes:
        - name: secrets-store
          csi:
            driver: secrets-store.csi.k8s.io
            readOnly: true
            volumeAttributes:
              secretProviderClass: visign-kv-secrets
      containers:
        - name: visign-web
          volumeMounts:
            - name: secrets-store
              mountPath: "/mnt/secrets-store"
              readOnly: true
```

### 6C. Deploy Secret Provider

```bash
# Replace placeholders
KV_NAME="your-keyvault-name"
TENANT_ID=$(az account show --query tenantId -o tsv)

sed -i "s|__KV_NAME__|$KV_NAME|g" k8s/secrets-provider.yaml
sed -i "s|__TENANT_ID__|$TENANT_ID|g" k8s/secrets-provider.yaml

kubectl apply -f k8s/secrets-provider.yaml
```

---

## Quick Reference: Order of Operations

```
1. az login
2. az deployment group create (Bicep → ACR + AKS + Key Vault)
3. az aks get-credentials (connect to cluster)
4. az keyvault secret set (store secrets)
5. helm install ingress-nginx (install ingress controller)
6. helm install monitoring (install Prometheus+Grafana)
7. kubectl apply -f k8s/ (deploy everything)
8. Push code to GitHub → GitHub Actions auto builds+deploys
9. Access Grafana → set up dashboards
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `ImagePullBackOff` | ACR not attached to AKS. Run: `az aks update -n visign-aks -g visign-rg --attach-acr <acr-name>` |
| Pod stuck `Pending` | Not enough resources. Check: `kubectl describe pod <name> -n visign` |
| Ingress no external IP | Wait 2-3 min. Check: `kubectl get svc -n ingress-nginx` |
| Grafana not loading | Check pod: `kubectl logs -n monitoring -l app.kubernetes.io/name=grafana` |
| Bicep deployment fails | Check: `az deployment group show -g visign-rg -n main --query properties.error` |
| CI/CD deploy fails | Check GitHub Actions logs. Ensure `AZURE_CREDENTIALS` secret is set correctly |
| `required variable TORCH_COMPUTE is missing a value` in `docker compose build` | Add `TORCH_COMPUTE=cpu` or `TORCH_COMPUTE=gpu` to repo-root `.env` |
| `docker-credential-desktop` not found | Remove `"credsStore": "desktop"` from `~/.docker/config.json`, then run `docker login` |
| `next: not found` during Docker build | In Dockerfile use `npm ci --include=dev` in build stage, then rebuild with `--no-cache` |
| AI build times out downloading CUDA wheels | Install CPU-only torch from `https://download.pytorch.org/whl/cpu` and use runtime-only requirements |
| `No database connection string was provided to neon()` during `npm run build` | Add `export const dynamic = "force-dynamic"` in DB-backed route layouts (e.g. `(main)` and `lesson`), and make sure `DATABASE_URL` is set in repo-root `.env` before running `docker compose build` |
