targetScope = 'resourceGroup'

param accountName string

@secure()
@description('Connection property bags preserve source API fields not yet represented in Bicep types, including ProjectManagedIdentity authentication.')
param connectionDefinitions object

resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: accountName
}

resource accountConnections 'Microsoft.CognitiveServices/accounts/connections@2026-09-01' = [for connection in items(connectionDefinitions): {
  parent: account
  name: connection.key
  properties: connection.value
}]
