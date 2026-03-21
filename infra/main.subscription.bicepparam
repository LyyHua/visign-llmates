using './main.subscription.bicep'

param resourceGroupName = 'visign-rg'
param projectName = 'visign'
param location = 'southeastasia'
param aksNodeCount = 2
param aksNodeVMSize = 'Standard_B2s'
param aksAvailabilityZones = [
	'2'
	'3'
]
