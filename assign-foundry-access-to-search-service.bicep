
targetScope = 'resourceGroup'

param foundryAccountResourceName string
param searchServiceName string


param cognitiveServicesOpenAIUserRoleDefinitionID string = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'

@description('Generate a unique GUID to use as name for the role assignment')
var containerAppToAcrRoleAssignmentName = guid(searchService.id, cognitiveServicesOpenAIUserRoleDefinitionID, foundryAccountResource.id)

resource foundryAccountResource 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryAccountResourceName
}

resource searchService 'Microsoft.Search/searchServices@2026-03-01-preview' existing = {
  name: searchServiceName
}

resource searchServiceToFoundryRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundryAccountResource
  name: containerAppToAcrRoleAssignmentName
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesOpenAIUserRoleDefinitionID)
    principalId: searchService.identity.principalId
    principalType: 'ServicePrincipal'
  }
}
