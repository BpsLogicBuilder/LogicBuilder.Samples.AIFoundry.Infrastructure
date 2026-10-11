targetScope = 'resourceGroup'

param searchServiceName string
param principalIds string[]

var readerRoleId = '1407120a-92aa-4202-b7e9-c0e197c71c8f'

resource searchService 'Microsoft.Search/searchServices@2026-03-01-preview' existing = {
  name: searchServiceName
}

resource principalToSearchServiceRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for principalId in principalIds: {
  name: guid(searchService.id, principalId, readerRoleId)
  scope: searchService
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', readerRoleId)
  }
}]
