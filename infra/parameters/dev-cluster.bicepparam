using '../main.bicep'

// SEPARATE DEV CLUSTER MODE: Dedicated AKS for development
// Best for: Enterprise, true isolation, production workloads

param clusterMode = 'separate'
param environment = 'dev'
param projectName = 'visign'
param location = 'southeastasia'
param aksAvailabilityZones = [
  '2'
  '3'
]
param aksNodeCount = 1
param aksAutoScaleMin = 1
param aksAutoScaleMax = 2
