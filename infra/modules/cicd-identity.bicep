// CI/CD Managed Identity module
// Creates a user-assigned managed identity for GitHub Actions deployments

param location string
param identityName string

// User-assigned managed identity
resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
}

output identityId string = identity.id
output identityClientId string = identity.properties.clientId
output identityPrincipalId string = identity.properties.principalId
output identityResourceId string = identity.id
