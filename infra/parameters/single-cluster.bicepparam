using '../main.bicep'

// SINGLE CLUSTER MODE: One AKS cluster with two namespaces
// Best for: Student accounts, learning, cost optimization, non-critical apps

param clusterMode = 'single'
param environment = 'dev'  // Only used for ACR/KV naming suffix
param projectName = 'visign'
param location = 'southeastasia'
param aksAvailabilityZones = [
  '2'
  '3'
]
