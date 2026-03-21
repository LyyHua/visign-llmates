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
