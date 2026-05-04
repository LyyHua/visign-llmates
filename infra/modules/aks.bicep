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

@description('Autoscale minimum node count')
param autoScaleMin int = 1

@description('Autoscale maximum node count')
param autoScaleMax int = 4

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
        minCount: autoScaleMin
        maxCount: autoScaleMax
        maxPods: 110
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
output csiIdentityObjectId string = aks.properties.addonProfiles.azureKeyvaultSecretsProvider.identity.objectId
