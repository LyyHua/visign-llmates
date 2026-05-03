@description('Resource group name')
param resourceGroupName string = 'visign-rg'

@description('Location for the resource group')
param location string = resourceGroup().location

@description('Path to the main Bicep file')
param mainTemplate string = 'main.bicep'

@description('Parameters file path')
param parametersFile string = ''

// Create the resource group at subscription scope
// Note: This file MUST be deployed with 'az deployment sub create' to create the RG first
targetScope = 'subscription'

resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: resourceGroupName
  location: location
  tags: {
    Project: 'visign'
    Environment: 'dev'
  }
}

// Deploy the main infrastructure into the created resource group
module platform mainTemplate = {
  scope: rg
  name: 'deploy-visign-platform'
  #if parametersFile != ''
  params: {
    // Parameters will be loaded from the parameters file
  }
  #endif
}
