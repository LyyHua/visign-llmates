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
param aksAvailabilityZones array = [
  '2'
  '3'
]

@description('AKS autoscale minimum node count')
param aksAutoScaleMin int = 1

@description('AKS autoscale maximum node count')
param aksAutoScaleMax int = 4

@description('ACR SKU')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
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
  name: 'deploy-acr-dev'
  scope: rg
  params: {
    acrName: '${projectName}dacr${uniqueString(rg.id)}'
    location: location
    acrSku: acrSku
  }
}

// Deploy PROD ACR
module acrProd 'modules/acr.bicep' = {
  name: 'deploy-acr-prod'
  scope: rg
  params: {
    acrName: '${projectName}pacr${uniqueString(rg.id)}'
    location: location
    acrSku: acrSku
  }
}

// Deploy DEV Key Vault
module keyVaultDev 'modules/keyvault.bicep' = {
  name: 'deploy-kv-dev'
  scope: rg
  params: {
    keyVaultName: '${projectName}dkv${uniqueString(rg.id)}'
    location: location
    tenantId: subscription().tenantId
    softDeleteRetentionDays: keyVaultSoftDeleteDays
  }
}

// Deploy PROD Key Vault
module keyVaultProd 'modules/keyvault.bicep' = {
  name: 'deploy-kv-prod'
  scope: rg
  params: {
    keyVaultName: '${projectName}pkv${uniqueString(rg.id)}'
    location: location
    tenantId: subscription().tenantId
    softDeleteRetentionDays: keyVaultSoftDeleteDays
  }
}

// Deploy CI/CD Managed Identity
module cicdIdentity 'modules/cicd-identity.bicep' = {
  name: 'deploy-cicd-identity'
  scope: rg
  params: {
    location: location
    identityName: '${projectName}cicd${uniqueString(rg.id)}'
  }
}

// Deploy AKS (shared across environments, attached to dev ACR by default)
module aks 'modules/aks.bicep' = {
  name: 'deploy-aks'
  scope: rg
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

// Assign role permissions to CI/CD identity for DEV ACR
module acrDevRoleAssignment 'modules/role-assignment.bicep' = {
  name: 'deploy-acr-dev-role'
  scope: rg
  params: {
    targetResourceId: acrDev.outputs.acrId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8311e382-0749-4cb8-b61a-304f252e45ec') // AcrPush
    principalId: cicdIdentity.outputs.identityPrincipalId
  }
}

// Assign role permissions to CI/CD identity for PROD ACR
module acrProdRoleAssignment 'modules/role-assignment.bicep' = {
  name: 'deploy-acr-prod-role'
  scope: rg
  params: {
    targetResourceId: acrProd.outputs.acrId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8311e382-0749-4cb8-b61a-304f252e45ec') // AcrPush
    principalId: cicdIdentity.outputs.identityPrincipalId
  }
}

// Assign role permissions to CI/CD identity for DEV Key Vault
module keyVaultDevRoleAssignment 'modules/role-assignment.bicep' = {
  name: 'deploy-kv-dev-role'
  scope: rg
  params: {
    targetResourceId: keyVaultDev.outputs.keyVaultId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7') // Key Vault Secrets Officer
    principalId: cicdIdentity.outputs.identityPrincipalId
  }
}

// Assign role permissions to CI/CD identity for PROD Key Vault
module keyVaultProdRoleAssignment 'modules/role-assignment.bicep' = {
  name: 'deploy-kv-prod-role'
  scope: rg
  params: {
    targetResourceId: keyVaultProd.outputs.keyVaultId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7') // Key Vault Secrets Officer
    principalId: cicdIdentity.outputs.identityPrincipalId
  }
}

// Assign role permissions to CI/CD identity for AKS
module aksRoleAssignment 'modules/role-assignment.bicep' = {
  name: 'deploy-aks-role'
  scope: rg
  params: {
    targetResourceId: aks.outputs.aksId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b') // Azure Kubernetes Service RBAC Cluster Admin
    principalId: cicdIdentity.outputs.identityPrincipalId
  }
}

// Assign role permissions to AKS for PROD ACR pull (in addition to dev ACR pull in aks.bicep)
module aksProdPullRoleAssignment 'modules/role-assignment.bicep' = {
  name: 'deploy-aks-prod-pull-role'
  scope: rg
  params: {
    targetResourceId: acrProd.outputs.acrId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull (built-in role)
    principalId: aks.outputs.kubeletIdentityObjectId
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