using '../main.subscription.bicep'

param environment = 'prod'
param resourceGroupName = 'visign-rg'
param projectName = 'visign'
param location = 'southeastasia'

param aksNodeCount = 2
param aksNodeVMSize = 'Standard_B2s'
param aksAvailabilityZones = [
  '2'
  '3'
]
param aksAutoScaleMin = 1
param aksAutoScaleMax = 4

param acrSku = 'Basic'
param keyVaultSoftDeleteDays = 7
