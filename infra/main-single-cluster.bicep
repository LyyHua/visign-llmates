// Single-cluster deployment with separate ACR/KeyVault per environment
// Deploy with: az deployment sub create --template-file main-single-cluster.bicep

targetScope = 'subscription'

@description('Resource group name')
param resourceGroupName string = 'visign-rg'

@description('Location for the resource group')
param location string = 'southeastasia'

@description('Project name used as prefix')
param projectName string = 'visign'

@description('AKS availability zones')
param aksAvailabilityZones array = ['2', '3']

@description('AKS autoscale minimum node count')
param aksAutoScaleMin int = 1

@description('AKS autoscale maximum node count')
param aksAutoScaleMax int = 4

@description('ACR SKU')
param acrSku string = 'Basic'

@description('Key Vault soft delete retention in days')
param keyVaultSoftDeleteDays int = 7

// Create the resource group
resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: resourceGroupName
  location: location
  tags: {
    Project: projectName
    Deployment: 'single-cluster-multi-env'
    ManagedBy: 'Bicep'
  }
}

// Deploy DEV ACR
module acrDev 'modules/acr.bicep' = {
  scope: rg
  name: 'deploy-acr-dev'
  params: {
    acrName: '${projectName}dacr${uniqueString(rg.id)}'
    location: location
    acrSku: acrSku
  }
}

// Deploy PROD ACR
module acrProd 'modules/acr.bicep' = {
  scope: rg
  name: 'deploy-acr-prod'
  params: {
    acrName: '${projectName}pacr${uniqueString(rg.id)}'
    location: location
    acrSku: acrSku
  }
}

// Deploy DEV Key Vault
module keyVaultDev 'modules/keyvault.bicep' = {
  scope: rg
  name: 'deploy-kv-dev'
  params: {
    keyVaultName: '${projectName}dkv${uniqueString(rg.id)}'
    location: location
    tenantId: subscription().tenantId
    softDeleteRetentionDays: keyVaultSoftDeleteDays
  }
}

// Deploy PROD Key Vault
module keyVaultProd 'modules/keyvault.bicep' = {
  scope: rg
  name: 'deploy-kv-prod'
  params: {
    keyVaultName: '${projectName}pkv${uniqueString(rg.id)}'
    location: location
    tenantId: subscription().tenantId
    softDeleteRetentionDays: keyVaultSoftDeleteDays
  }
}

// Deploy CI/CD Managed Identity
module cicdIdentity 'modules/cicd-identity.bicep' = {
  scope: rg
  name: 'deploy-cicd-identity'
  params: {
    location: location
    identityName: '${projectName}cicd${uniqueString(rg.id)}'
    rgName: rg.name
  }
}

// Deploy AKS (shared across environments, attached to dev ACR by default)
module aks 'modules/aks.bicep' = {
  scope: rg
  name: 'deploy-aks'
  params: {
    aksName: '${projectName}-aks'
    location: location
    nodeCount: 2
    nodeVMSize: 'Standard_B2s'
    nodeAvailabilityZones: aksAvailabilityZones
    autoScaleMin: aksAutoScaleMin
    autoScaleMax: aksAutoScaleMax
    acrId: acrDev.outputs.acrId
  }
}


// Outputs - DEV resources
output devAcrLoginServer string = acrDev.outputs.acrLoginServer
output devAcrName string = acrDev.outputs.acrName
output devKeyVaultName string = keyVaultDev.outputs.keyVaultName
output devKeyVaultUri string = keyVaultDev.outputs.keyVaultUri

// Outputs - PROD resources
output prodAcrLoginServer string = acrProd.outputs.acrLoginServer
output prodAcrName string = acrProd.outputs.acrName
output prodKeyVaultName string = keyVaultProd.outputs.keyVaultName
output prodKeyVaultUri string = keyVaultProd.outputs.keyVaultUri

// Outputs - Shared resources
output aksName string = aks.outputs.aksName
output resourceGroupName string = rg.name

// Outputs - CI/CD Identity
output cicdIdentityId string = cicdIdentity.outputs.identityId
output cicdIdentityClientId string = cicdIdentity.outputs.identityClientId
output cicdIdentityPrincipalId string = cicdIdentity.outputs.identityPrincipalId
