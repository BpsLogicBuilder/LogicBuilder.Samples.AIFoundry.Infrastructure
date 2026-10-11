targetScope = 'resourceGroup'

param location string
param functionAuthClientId string
@secure()
param functionAuthClientSecret string
param modelDeployments array

var suffix = uniqueString(subscription().subscriptionId, resourceGroup().id)
var foundryAccountResourceName = 'bps-foundry-iq-${suffix}'
var foundryProjectName = 'bps-10092026'
var searchServiceName = 'bps-search-iq-${suffix}'
var functionAppName = 'bps-app-iq-${suffix}'
var functionStorageName = 'bpsappstr${suffix}'
var documentStorageName = 'bpsiqdocs${suffix}'
var packageContainerName = 'app-package-${functionAppName}'
var storageRoleIds = [
  'b7e6dc6d-f1e8-4753-8033-0f276bb0955b' //Storage Blob Data Owner
  '974c5e8b-45b9-4653-ba55-5f855dd0fb88' //Storage Queue Data Contributor 
  'ba92f5b4-2d11-453d-a403-e96b0029c9fe' //Storage Blob Data Contributor
  '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3' //Storage Table Data Contributor
]

resource foundryAccountResource 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryAccountResourceName
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2026-09-01' = {
  parent: foundryAccountResource
  name: foundryProjectName
  location: location
  identity: { type: 'SystemAssigned' }
  dependsOn: [foundry]
  properties: {}
}

resource searchService 'Microsoft.Search/searchServices@2026-03-01-preview' = {
  name: searchServiceName
  location: location
  sku: { name: 'basic' } //Serverless sku fails to provision with System Assigned managed identity.
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hostingMode: 'Default'
    computeType: 'Default'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    semanticSearch: 'standard'
    authOptions: {
      aadOrApiKey: { aadAuthFailureMode: 'http401WithBearerChallenge' }
    }
    networkRuleSet: { bypass: 'None' }
    encryptionWithCmk: { enforcement: 'Unspecified' }
  }
}

module functionIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.6.0' = {
  name: 'function-identity'
  params: {
    name: '${functionAppName}-uami'
    location: location
    enableTelemetry: false
  }
}

module logAnalyticsWorkspaces 'br/public:avm/res/operational-insights/workspace:0.16.1' = [for purpose in ['foundry', 'function']: {
  name: '${purpose}-la-workspace'
  params: {
    name: 'bps-${purpose}-logs-${suffix}'
    location: location
    skuName: 'PerGB2018'
    dataRetention: 30
    dailyQuotaGb: '-1'
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    enableTelemetry: false
  }
}]

module foundryInsights 'br/public:avm/res/insights/component:0.8.0' = {
  name: 'foundry-insights'
  params: {
    name: 'bps-foundry-appinsights-${suffix}'
    location: location
    kind: 'web'
    applicationType: 'web'
    workspaceResourceId: logAnalyticsWorkspaces[0].outputs.resourceId
    retentionInDays: 90
    disableLocalAuth: false
    disableIpMasking: false
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    enableTelemetry: false
  }
}

module functionInsights 'br/public:avm/res/insights/component:0.8.0' = {
  name: 'function-insights'
  params: {
    name: 'bps-function-appinsights-${suffix}'
    location: location
    kind: 'web'
    applicationType: 'web'
    workspaceResourceId: logAnalyticsWorkspaces[1].outputs.resourceId
    retentionInDays: 90
    disableLocalAuth: true
    disableIpMasking: false
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    roleAssignments: [
      {
        principalId: functionIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: '3913510d-42f4-4e42-8a64-420c390055eb' //Monitoring Metrics Publisher 
      }
    ]
    enableTelemetry: false
  }
}

module functionStorage 'br/public:avm/res/storage/storage-account:0.33.1' = {
  name: 'function-storage'
  params: {
    name: functionStorageName
    location: location
    kind: 'StorageV2'
    skuName: 'Standard_LRS'
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }
    blobServices: {
      containerDeleteRetentionPolicyEnabled: false
      deleteRetentionPolicyEnabled: false
      containers: [
        { name: packageContainerName, publicAccess: 'None' }
        { name: 'azure-webjobs-hosts', publicAccess: 'None' }
        { name: 'azure-webjobs-secrets', publicAccess: 'None' }
      ]
    }
    roleAssignments: [for roleId in storageRoleIds: {
      principalId: functionIdentity.outputs.principalId
      principalType: 'ServicePrincipal'
      roleDefinitionIdOrName: roleId
    }]
    enableTelemetry: false
  }
}

module documentStorage 'br/public:avm/res/storage/storage-account:0.33.1' = {
  name: 'document-storage'
  params: {
    name: documentStorageName
    location: location
    kind: 'StorageV2'
    skuName: 'Standard_LRS'
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }
    blobServices: {
      containerDeleteRetentionPolicyEnabled: true
      containerDeleteRetentionPolicyDays: 7
      deleteRetentionPolicyEnabled: true
      deleteRetentionPolicyDays: 7
      containers: [{ name: 'contosoproducts', publicAccess: 'None' }]
    }
    enableTelemetry: false
  }
}

module functionPlan 'br/public:avm/res/web/serverfarm:0.7.0' = {
  name: 'function-plan'
  params: {
    name: 'bps-plan-iq-${suffix}'
    location: location
    kind: 'functionapp'
    reserved: true
    skuName: 'FC1'
    skuCapacity: 0
    zoneRedundant: false
    maximumElasticWorkerCount: 1
    enableTelemetry: false
  }
}

module foundry 'br/public:avm/res/cognitive-services/account:0.19.1' = {
  name: 'foundry-account'
  params: {
    name: foundryAccountResourceName
    location: location
    kind: 'AIServices'
    sku: 'S0'
    customSubDomainName: foundryAccountResourceName
    allowProjectManagement: true
    disableLocalAuth: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }
    managedIdentities: { systemAssigned: true }
    deployments: modelDeployments
    enableTelemetry: false
  }
}

module principalToSearchServiceRoleAssignments './search-rbac.bicep' = {
  name: 'search-service-role-assignments'
  params: {
    searchServiceName: searchService.name
    principalIds: [foundry.outputs.systemAssignedMIPrincipalId!, foundryProject.identity.principalId!]
  }
}

module searchServiceToFoundryRoleAssignment './assign-foundry-access-to-search-service.bicep' = {
  name: 'search-service-to-foundry-role-assignment'
  params: {
    searchServiceName: searchService.name
    foundryAccountResourceName: foundryAccountResourceName
  }
  dependsOn: [foundryProject]
}

module functionApp 'br/public:avm/res/web/site:0.24.0' = {
  name: 'function-app'
  params: {
    name: functionAppName
    location: location
    kind: 'functionapp,linux'
    serverFarmResourceId: functionPlan.outputs.resourceId
    managedIdentities: {
      userAssignedResourceIds: [functionIdentity.outputs.resourceId]
    }
    httpsOnly: true
    clientAffinityEnabled: false
    publicNetworkAccess: 'Enabled'
    siteConfig: { alwaysOn: false }
    functionAppConfig: {
      runtime: { name: 'dotnet-isolated', version: '10.0' }
      scaleAndConcurrency: { maximumInstanceCount: 100, instanceMemoryMB: 2048 }
      deployment: {
        storage: {
          type: 'blobContainer'
          value: 'https://${functionStorageName}.blob.${environment().suffixes.storage}/${packageContainerName}'
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: functionIdentity.outputs.resourceId
          }
        }
      }
    }
    configs: [
      {
        name: 'appsettings'
        properties: {
          AzureWebJobsStorage__accountName: functionStorageName
          AzureWebJobsStorage__credential: 'managedidentity'
          AzureWebJobsStorage__clientId: functionIdentity.outputs.clientId
          APPINSIGHTS_INSTRUMENTATIONKEY: functionInsights.outputs.instrumentationKey
          APPLICATIONINSIGHTS_AUTHENTICATION_STRING: 'ClientId=${functionIdentity.outputs.clientId};Authorization=AAD'
          WEBSITE_AUTH_AAD_ALLOWED_TENANTS: tenant().tenantId
          WEBSITE_AUTH_PRM_DEFAULT_WITH_SCOPES: 'api://${functionAuthClientId}/user_impersonation'
          MICROSOFT_PROVIDER_AUTHENTICATION_SECRET: functionAuthClientSecret
        }
      }
      {
        name: 'authsettingsV2'
        properties: {
          platform: { enabled: true, runtimeVersion: '~1' }
          globalValidation: { requireAuthentication: true, unauthenticatedClientAction: 'Return401', excludedPaths: [] }
          httpSettings: {
            requireHttps: true
            routes: { apiPrefix: '/.auth' }
            forwardProxy: { convention: 'NoProxy' }
          }
          identityProviders: {
            azureActiveDirectory: {
              enabled: true
              registration: {
                clientId: functionAuthClientId
                clientSecretSettingName: 'MICROSOFT_PROVIDER_AUTHENTICATION_SECRET'
                openIdIssuer: 'https://sts.windows.net/${tenant().tenantId}/v2.0'
              }
              validation: { allowedAudiences: ['api://${functionAuthClientId}'] }
              login: { disableWWWAuthenticate: false }
            }
          }
          login: {
            tokenStore: { enabled: true, tokenRefreshExtensionHours: 72 }
            cookieExpiration: { convention: 'FixedTime', timeToExpiration: '08:00:00' }
            nonce: { validateNonce: true, nonceExpirationInterval: '00:05:00' }
            preserveUrlFragmentsForLogins: false
          }
        }
      }
    ]
    roleAssignments: [
      {
        principalId: foundryProject.identity.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'de139f84-1756-47ae-9be6-808fbbe84772'
      }
    ]
    tags: {
      'hidden-link: /app-insights-resource-id': functionInsights.outputs.resourceId
    }
    enableTelemetry: false
  }
  dependsOn: [functionStorage]
}

module connections './connections.bicep' = {
  name: 'foundry-connections'
  params: {
    accountName: foundryAccountResource.name
    connectionDefinitions: {
      btaylor8669foundryiqri3r10c: {
        authType: 'ApiKey'
        category: 'AppInsights'
        group: 'ServicesAndApps'
        isDefault: true
        isSharedToAll: false
        useWorkspaceManagedIdentity: false
        target: foundryInsights.outputs.resourceId
        credentials: { key: foundryInsights.outputs.connectionString }
        metadata: {
          ApiType: 'Azure'
          ApplicationInsightsConnectionString: foundryInsights.outputs.connectionString
          ResourceId: foundryInsights.outputs.resourceId
          displayName: foundryInsights.outputs.name
        }
      }
      btaylor8983foundryiqi3r10c: {
        authType: 'ApiKey'
        category: 'CognitiveSearch'
        group: 'AzureAI'
        isDefault: true
        isSharedToAll: false
        useWorkspaceManagedIdentity: false
        target: '${searchService.properties.endpoint}/'
        credentials: { key: searchService.listAdminKeys().primaryKey }
        metadata: {
          ApiType: 'Azure'
          ApiVersion: '2024-05-01-preview'
          DeploymentApiVersion: '2023-11-01'
          ResourceId: searchService.id
          displayName: searchService.name
          type: 'azure_ai_search'
        }
      }
      'kb-knowledgebase576-3r10c': {
        authType: 'CustomKeys'
        category: 'RemoteTool'
        group: 'GenericProtocol'
        isDefault: true
        isSharedToAll: false
        useWorkspaceManagedIdentity: false
        target: '${searchService.properties.endpoint}/knowledgebases/knowledgebase576/mcp?api-version=2026-08-01-preview'
        credentials: { keys: { 'api-key': searchService.listAdminKeys().primaryKey } }
        metadata: { knowledgeBaseName: 'knowledgebase576', type: 'knowledgeBase_MCP' }
      }
      GreetingTool: {
        authType: 'ProjectManagedIdentity'
        audience: 'api://${functionAuthClientId}'
        category: 'RemoteTool'
        group: 'GenericProtocol'
        isDefault: false
        isSharedToAll: false
        useWorkspaceManagedIdentity: false
        target: 'https://${functionApp.outputs.defaultHostname}/runtime/webhooks/mcp'
        metadata: { type: 'custom_MCP' }
      }
    }
  }
}

output resources object = {
  foundryAccount: foundry.outputs.resourceId
  foundryAccountResourceName: foundryAccountResourceName
  foundryProject: foundryProject.id
  foundryProjectEndPoint: foundryProject.properties.endpoints['AI Foundry API']
  foundryIQMcpToolUrl: '${searchService.properties.endpoint}/knowledgebases/knowledgebase576/mcp?api-version=2026-08-01-preview'
  greeterMcpToolUrl: 'https://${functionAppName}.azurewebsites.net/runtime/webhooks/mcp'
  searchService: searchService.id
  functionApp: functionApp.outputs.resourceId
  functionAppName: functionAppName
  functionAppUrl: 'https://${functionApp.outputs.defaultHostname}'
  functionStorage: functionStorage.outputs.resourceId
  documentStorage: documentStorage.outputs.resourceId
}

output managedIdentityPrincipalIds object = {
  foundryAccount: foundry.outputs.systemAssignedMIPrincipalId!
  foundryProject: foundryProject.identity.principalId
  functionUserAssignedIdentity: functionIdentity.outputs.principalId
}
