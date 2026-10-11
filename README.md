# Foundry IQ infrastructure replica

Reviewed on 2026-10-07 in Microsoft Azure Sponsorship
(`<sub>`), tenant
`<tenant>`.

`main.bicep` is a subscription-scoped entrypoint. It creates
`bps-foundry-iq-new` in `centralus` and invokes `resources.bicep`.
Keep `connections.bicep` and `search-rbac.bicep` alongside these files.
Azure Verified Modules are version-pinned and restored during compilation.
Template generation does not deploy resources. See the connection recovery
notes below for the subsequent user-run deployment attempt.

## Inventory

The source group contains these 12 resources. New resource names use a
deterministic suffix based on the destination subscription and resource group.
The project name and scoped connection names are retained.

| Source resource | Type | Recreation |
| --- | --- | --- |
| btaylor-8669-foundry-iq-resource | Foundry AIServices account | S0, system-assigned identity, project management enabled |
| btaylor-8669-foundry-iq-resource/btaylor-8983 | Foundry project | System-assigned identity |
| btaylor-8983-foundry-iq | AI Search | Serverless preview SKU, standard semantic search |
| bpsfoundryidstorage | Document storage | StorageV2, Standard_LRS, Hot, seven-day blob/container soft delete |
| bpsappstrwsv3pvhlxkiz6 | Function storage | StorageV2, Standard_LRS, Hot, shared keys and soft delete disabled |
| bps-app-wsv3pvhlxkiz6-uami | User-assigned identity | New identity attached to the new Function App |
| bps-plan-wsv3pvhlxkiz6 | Function hosting plan | Linux Flex Consumption, FC1 |
| bps-app-wsv3pvhlxkiz6 | Function App | .NET isolated 10.0, 2048 MB, maximum 100 instances, Entra authentication |
| bps-log-wsv3pvhlxkiz6 | Function Log Analytics workspace | PerGB2018, 30-day retention, unlimited daily quota |
| btaylor-8669-foundry-iq-resource-logs | Foundry Log Analytics workspace | PerGB2018, 30-day retention, unlimited daily quota |
| bps appi-wsv3pvhlxkiz6 | Function Application Insights | Workspace-based, 90-day retention, local auth disabled |
| btaylor-8669-foundry-iq-resource-appinsights | Foundry Application Insights | Workspace-based, 90-day retention |

Child-resource discovery also found three OpenAI model deployments,
four blob containers, and four connection names at both Foundry account
and project scopes. The two connection listings are not independent sets:
the template writes each connection once at its account-owned scope rather
than attempting to create it again through the project API. Connections are
included with endpoints, resource IDs,
telemetry connection strings, and Search keys bound to the new resources.
The Function deployment-container name is also rewritten.

No Foundry account diagnostic setting was present.

## Managed identity roles

All eight observed assignments are recreated at equivalent new-resource scopes.
No grants to users, groups, or ordinary application service principals are copied.
Managed identities are themselves represented by `ServicePrincipal` in Azure RBAC;
filtering used the actual identity principal IDs, not just that principal type.
No additional inherited assignments were found for these identities at the
source resource-group scope.

| New identity | New scope | Role |
| --- | --- | --- |
| Foundry account system identity | Search service | Search Index Data Reader |
| Foundry project system identity | Search service | Search Index Data Reader |
| Foundry project system identity | Function App | Website Contributor |
| Function user-assigned identity | Function storage | Storage Blob Data Owner |
| Function user-assigned identity | Function storage | Storage Blob Data Contributor |
| Function user-assigned identity | Function storage | Storage Queue Data Contributor |
| Function user-assigned identity | Function storage | Storage Table Data Contributor |
| Function user-assigned identity | Function Application Insights | Monitoring Metrics Publisher |

The overlapping Blob Owner and Blob Contributor grants are intentional: both
exist in the source. Assignment GUIDs incorporate the new scope, principal ID,
and role, rather than reusing source assignment IDs.

## Deployment

Provide `functionAuthClientSecret` securely, preferably through a Key Vault
secret reference in an external ARM parameter file. It has no default and
is passed through secure parameters. Do not put a literal secret in this repo.
Key Vault references require the vault's template-deployment setting and
the deploying principal's appropriate access.

The default `functionAuthClientId` reuses the source Entra app registration
`26e88ca2-f412-43d5-bab8-013351d8f92c`. Entra app registrations, client secrets,
and redirect URIs are outside this Azure resource-group template. Supply its
valid secret, or override both authentication parameters for another
registration. Browser sign-in may require adding the new Function hostname's
`/.auth/login/aad/callback` redirect URI to that registration.

From this folder, preview before deploying. Replace the external parameter-file
path with your own secure file:

```powershell
az deployment sub what-if `
  --subscription <sub> `
  --location centralus `
  --template-file main.bicep `
  --parameters '@C:\secure\foundry.parameters.json'
```

After reviewing the preview, use the same arguments with
`az deployment sub create`. The deployment identity needs permission to create
resources and role assignments. Outputs expose resource IDs, the Function URL,
and all three newly generated managed-identity principal IDs, not credentials.

### Connection Ownership Recovery

The first user-run deployment on 2026-10-07 successfully created all four
account-scoped connections, then failed when the template tried to write the
same names through the project API. The `UserError` messages identify the
account's backing workspace as the owner; this was not a resource-group
creation race or a missing dependency.

The corrected template retains the account-scoped writes and removes the
duplicate project-scoped writes. Rerun the original deployment against the
same group to update the existing account-owned connections. Do not delete
the resource group or connections to resolve this error. Other deployment
prerequisites and possible failures still apply.

## Review Notes And Limits

- The source uses public network access on Foundry, Search, and storage. Local
  key authentication remains enabled on Foundry, Search, and document storage.
  These settings are preserved, not hardened as part of the recreation.
- Models use GlobalStandard with capacities 50 (`gpt-5`, version 2025-08-07),
  120 (`text-embedding-3-small`, version 1), and 3750 (`gpt-5.2`, version
  2025-12-11). Cloning requires additional available model quota and model/SKU
  availability. Override `modelDeployments` to change capacities or supply an
  empty array to defer model deployment.
- Serverless Search requires subscription/region access to that preview SKU.
  Its resource is explicit because the verified Search module does not yet
  support serverless. The region and pricing of the new resources should be
  reviewed before deployment.
- ARM server-generated IDs, timestamps, endpoints, identity object IDs,
  licensing state, and provisioning status are not copied. Foundry project
  default selection and generated agent-identity state are service-managed.
- `ProjectManagedIdentity` connection authentication and additional source
  connection metadata are passed as secure property bags because the current
  Bicep connection type definitions do not describe all observed API fields.
- This is infrastructure recreation, not data or application migration.
  Function packages, host/function secrets, blobs, Search indexes/indexers/data
  sources/skillsets/knowledge bases, Foundry agents, and telemetry history are
  not copied. Deploy the Function code and migrate content separately.
  The recreated knowledge-base connection will not be usable until
  `knowledgebase576` exists in the new Search service.
- The corrected Bicep template compiles with no diagnostics. A compiled-template
  check verifies that only account-scoped connection writes remain. The
  user-run what-if reported nested-deployment short-circuiting, and the first
  deployment failed as described above. The corrected template has not been
  redeployed; quota, preview availability, and runtime behavior remain
  deployment-time checks.

## References

- [Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/)
- [Subscription-scoped Bicep deployments](https://learn.microsoft.com/azure/azure-resource-manager/bicep/deploy-to-subscription)
- [Bicep role assignments](https://learn.microsoft.com/azure/azure-resource-manager/bicep/scenarios-rbac)
- [Key Vault references in ARM parameter files](https://learn.microsoft.com/azure/azure-resource-manager/templates/key-vault-parameter)
- [Foundry project connections template reference](https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/accounts/projects/connections)

## Post Deployment Steps

- Deploy the Function App.
  From your desktop run: func azure functionapp publish "<deployed-function-app-name>"
  From GitHub Actions:
    - name: 'Publish Project'
      run: dotnet publish --configuration Release --output ./publish_output
    - name: 'Deploy to Azure Functions'
      uses: Azure/functions-action@v1
      with:
        app-name: '<deployed-function-app-name>'
        package: './publish_output'

- Add data to the deployed docs storage account. The sample search service uses Azure Blob Storage.
  storageId=$(az deployment group show --resource-group $rg --name main --query properties.outputs.resources.value.documentStorage --output tsv)
  echo $storageId
  BLOB_CONNECTION_STRING=$(az storage account show-connection-string --ids $storageId -o tsv)
  echo $BLOB_CONNECTION_STRING
  az storage blob upload-batch --destination "contosoproducts" --source "<UploadSourceFolder>" --connection-string "$BLOB_CONNECTION_STRING"
- Use the deployed storage account to create a knowledge base called knowledgebase576 in the Search Service resource. In the Azure portal, navigate to the search service and select "Knowledge bases" under Agentic retrieval.  Alternatively, in the Mocrosoft Foundary (make sure New Foundary is selected), then select Build/Knowledge/Create a Knowledge base and follow the prompts to link the storage account and create the knowledge base.