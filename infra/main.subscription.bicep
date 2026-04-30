targetScope = 'subscription'

@description('Environment name for deployment')
@allowed([
  'dev'
  'prod'
])
param environment string = 'dev'

@description('Base resource group name for Visign infrastructure')
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

@description('AKS autoscale minimum node count')
param aksAutoScaleMin int = environment == 'prod' ? 2 : 1

@description('AKS autoscale maximum node count')
param aksAutoScaleMax int = environment == 'prod' ? 6 : 4

@description('Azure Container Registry SKU')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param acrSku string = environment == 'prod' ? 'Standard' : 'Basic'

@description('Key Vault soft delete retention in days')
param keyVaultSoftDeleteDays int = environment == 'prod' ? 90 : 7

@description('Cluster mode: single (namespaces) or separate (dedicated clusters)')
@allowed([
  'single'
  'separate'
])
param clusterMode string = 'separate'

var rgName = '${resourceGroupName}-${environment}'

resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: rgName
  location: location
}

module platform './main.bicep' = {
  name: 'deploy-visign-platform-${environment}'
  scope: rg
  params: {
    projectName: projectName
    environment: environment
    location: location
    clusterMode: clusterMode
    aksNodeCount: aksNodeCount
    aksNodeVMSize: aksNodeVMSize
    aksAvailabilityZones: aksAvailabilityZones
    aksAutoScaleMin: aksAutoScaleMin
    aksAutoScaleMax: aksAutoScaleMax
    acrSku: acrSku
    keyVaultSoftDeleteDays: keyVaultSoftDeleteDays
  }
}

output resourceGroup string = rg.name
output acrLoginServer string = platform.outputs.acrLoginServer
output aksName string = platform.outputs.aksName
output keyVaultName string = platform.outputs.keyVaultName
output keyVaultUri string = platform.outputs.keyVaultUri
