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

output resourceGroup string = rg.name
output acrLoginServer string = platform.outputs.acrLoginServer
output aksName string = platform.outputs.aksName
output keyVaultName string = platform.outputs.keyVaultName
output keyVaultUri string = platform.outputs.keyVaultUri
