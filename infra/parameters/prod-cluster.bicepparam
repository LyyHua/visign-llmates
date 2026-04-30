using '../main.bicep'

// SEPARATE PROD CLUSTER MODE: Dedicated AKS for production
// Best for: Enterprise, customer-facing apps, compliance requirements

param clusterMode = 'separate'
param environment = 'prod'
param projectName = 'visign'
param location = 'southeastasia'
param aksAvailabilityZones = [
  '2'
  '3'
]
param aksNodeCount = 3
param aksAutoScaleMin = 2
param aksAutoScaleMax = 6
param acrSku = 'Standard'
param keyVaultSoftDeleteDays = 90
