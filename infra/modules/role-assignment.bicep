// Role assignment module
// Creates a role assignment for a principal on a target resource

param targetResourceId string
param roleDefinitionId string
param principalId string

// The role assignment name is a GUID that must be unique
var roleAssignmentName = guid(targetResourceId, roleDefinitionId, principalId)

// Create role assignment using a nested ARM deployment
// The role assignment is created at the target resource's scope via the deployment's resourceGroup
var targetResourceGroupName = split(targetResourceId, '/')[4]

resource roleAssignmentDeployment 'Microsoft.Resources/deployments@2022-09-01' = {
  name: 'ra-${uniqueString(targetResourceId, roleDefinitionId, principalId)}'
  resourceGroup: targetResourceGroupName
  properties: {
    mode: 'Incremental'
    template: {
      '$schema': 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
      contentVersion: '1.0.0.0'
      resources: [
        {
          type: 'Microsoft.Authorization/roleAssignments'
          apiVersion: '2022-04-01'
          name: roleAssignmentName
          properties: {
            roleDefinitionId: roleDefinitionId
            principalId: principalId
            principalType: 'ServicePrincipal'
          }
          scope: targetResourceId
        }
      ]
    }
  }
}