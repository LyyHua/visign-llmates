@description('Project name used as prefix')
param projectName string

@description('Deployment environment')
@allowed([
  'dev'
  'prod'
])
param environment string = 'dev'

@description('Azure region')
param location string = resourceGroup().location

@description('AKS node count')
param aksNodeCount int = 2

@description('AKS node VM size')
param aksNodeVMSize string = 'Standard_B2s'

@description('AKS availability zones for the system node pool')
param aksAvailabilityZones array

@description('AKS autoscale minimum node count')
param aksAutoScaleMin int = 1

@description('AKS autoscale maximum node count')
param aksAutoScaleMax int = 4

@description('Azure Container Registry SKU')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param acrSku string = 'Basic'

@description('Key Vault soft delete retention in days')
param keyVaultSoftDeleteDays int = 7

@description('Cluster mode: single (namespaces) or separate (dedicated clusters)')
@allowed([
  'single'
  'separate'
])
param clusterMode string = 'separate'

// Variables
var envSuffix = environment == 'prod' ? 'p' : 'd'
// In single mode: cluster named 'visign-aks' (both envs share it)
// In separate mode: cluster named 'visign-dev-aks' or 'visign-prod-aks'
var aksName = clusterMode == 'single' ? '${projectName}-aks' : '${projectName}-${environment}-aks'
// ACR names: NO HYPHENS allowed - only alphanumeric (https://docs.microsoft.com/en-us/azure/container-registry/)
var acrName = toLower('${projectName}${envSuffix}acr${uniqueString(resourceGroup().id)}')
// Key Vault names: can have hyphens but NOT consecutive hyphens
var kvName = toLower('${projectName}${envSuffix}kv${uniqueString(resourceGroup().id)}')

// Deploy ACR
module acr 'modules/acr.bicep' = {
  name: 'deploy-acr'
  params: {
    acrName: acrName
    location: location
    acrSku: acrSku
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
    autoScaleMin: aksAutoScaleMin
    autoScaleMax: aksAutoScaleMax
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
    softDeleteRetentionDays: keyVaultSoftDeleteDays
  }
}

// CI/CD Managed Identity - for GitHub Actions to deploy to AKS
// Enterprise practice: All infrastructure defined in IaC, no manual CLI commands
resource cicdIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${projectName}-cicd-identity'  // Single identity for both environments
  location: location
  tags: {
    Project: projectName
  }
}

// Reference existing ACR to establish scope for role assignment
resource acrRef 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

// Grant CI/CD identity access to ACR (pull/push images for CI/CD)
// Enterprise practice: Role assignments are declarative in Bicep, not manual CLI
resource cicdAcrRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: acrRef
  name: guid(resourceGroup().id, cicdIdentity.id, 'AcrPullPush')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8311e382-0749-4cb8-b61a-304f252e45ec') // ACR Contributor
    principalId: cicdIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Reference existing Key Vault to establish scope for role assignment
resource kvRef 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: kvName
}

// Grant CI/CD identity access to Key Vault (read secrets)
// Enterprise practice: Role assignments are declarative in Bicep, not manual CLI
resource cicdKvRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: kvRef
  name: guid(resourceGroup().id, cicdIdentity.id, 'KeyVaultReader')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74483') // Key Vault Secrets Officer
    principalId: cicdIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output acrLoginServer string = acr.outputs.acrLoginServer
output acrName string = acr.outputs.acrName
output aksName string = aks.outputs.aksName
output keyVaultName string = keyVault.outputs.keyVaultName
output keyVaultUri string = keyVault.outputs.keyVaultUri
output kubeletIdentityObjectId string = aks.outputs.kubeletIdentityObjectId
output cicdIdentityClientId string = cicdIdentity.properties.clientId
output cicdIdentityPrincipalId string = cicdIdentity.properties.principalId
