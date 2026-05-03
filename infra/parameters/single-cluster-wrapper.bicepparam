using '../main-single-cluster.bicep'

// Single-cluster deployment parameters
// Creates: 1 AKS (shared), 2 ACRs (dev/prod), 2 Key Vaults (dev/prod)

param resourceGroupName = 'visign-rg'
param location = 'southeastasia'
param projectName = 'visign'
param aksAvailabilityZones = [
  '2'
  '3'
]
param aksAutoScaleMin = 1
param aksAutoScaleMax = 4
param acrSku = 'Basic'
param keyVaultSoftDeleteDays = 7
