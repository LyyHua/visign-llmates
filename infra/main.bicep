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
var aksName = clusterMode == 'single' ? '${projectName}-aks' : '${projectName}-${environment}-aks'
var acrName = toLower('${projectName}${envSuffix}acr${uniqueString(resourceGroup().id)}')
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

// Deploy Key Vault
module keyVault 'modules/keyvault.bicep' = {
  name: 'deploy-keyvault'
  params: {
    keyVaultName: kvName
    location: location
    tenantId: subscription().tenantId
    softDeleteRetentionDays: keyVaultSoftDeleteDays
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

// CI/CD Managed Identity (created but role assignments done via CLI after deployment)
resource cicdIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${projectName}-cicd-identity'
  location: location
  tags: {
    Project: projectName
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
