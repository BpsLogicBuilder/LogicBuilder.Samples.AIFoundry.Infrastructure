@description('Source resources are deployed in Central US.')
param location string = resourceGroup().location

@description('Existing Entra app registration used by Function App authentication. This is not an Azure resource and is not recreated.')
param functionAuthClientId string = '26e88ca2-f412-43d5-bab8-013351d8f92c'

@secure()
@description('Client secret for the Entra app registration. Supply securely at deployment; never commit it.')
param functionAuthClientSecret string

@description('Model deployment capacities copied from the source. Additional available quota is required.')
param modelDeployments array = [
  {
    name: 'text-embedding-3-small'
    model: { format: 'OpenAI', name: 'text-embedding-3-small', version: '1' }
    sku: { name: 'GlobalStandard', capacity: 120 }
    raiPolicyName: 'Microsoft.DefaultV2'
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
  }
  {
    name: 'gpt-5.2'
    model: { format: 'OpenAI', name: 'gpt-5.2', version: '2025-12-11' }
    sku: { name: 'GlobalStandard', capacity: 3750 }
    raiPolicyName: 'Microsoft.DefaultV2'
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
  }
]

module infrastructure './resources.bicep' = {
  name: 'foundry-iq-infrastructure'
  params: {
    location: location
    functionAuthClientId: functionAuthClientId
    functionAuthClientSecret: functionAuthClientSecret
    modelDeployments: modelDeployments
  }
}

output resources object = infrastructure.outputs.resources
output managedIdentityPrincipalIds object = infrastructure.outputs.managedIdentityPrincipalIds
