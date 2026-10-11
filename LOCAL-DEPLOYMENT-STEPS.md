# Foundry Deployment steps

This document outlines the steps to deploy an AI Foundry Resource including an Foundry IQ Search resource and an MCP tool implemented using Azure Functions.

## Deploy the infrastructure using Bicep
rg="<resource goup name>"
az deployment group create --resource-group $rg --location centralus --template-file main.bicep --parameters '<PathToParameters.Json>'

## Deploy the Azure Functions MCP Tool
From the function project folder (PowerSHell):
    - Run `az login`
    - Run `$functionAppName=$(az deployment group show --resource-group $rg --name main --query properties.outputs.resources.value.functionAppName --output tsv)`
    - Run `func azure functionapp publish $functionAppName`

## Upload the search documents to the AI search storage account
Using Bash (preferable Ubuntu WSL)
    - Run `storageId=$(az deployment group show --resource-group $rg --name main --query properties.outputs.resources.value.documentStorage --output tsv)`
    - Run `storageId=$(echo "$storageId" | tr -d '\r')` (some cleanup is needed if you're on Windows to remove invalid characters)
    - Run `BLOB_CONNECTION_STRING=$(az storage account show-connection-string --ids $storageId -o tsv)`
    - Run `BLOB_CONNECTION_STRING=$(echo "$BLOB_CONNECTION_STRING" | tr -d '\r')`
    - Run `BLOB_CONTAINER_NAME="contosoproducts"` (contosoproducts is the container used in the bicep deployment)
    - Run `az storage blob upload-batch --destination "contosoproducts" --source "<PathToFolderOfPDFFiles>" --connection-string "$BLOB_CONNECTION_STRING"`

## Add a knowledge source and knowLedge base to the Foundry IQ Search Service
Using Bash
    - Run `search_token=$(az account get-access-token --scope https://search.azure.com/.default --query accessToken -o tsv)`
    - Run `search_token=$(echo "$search_token" | tr -d '\r') `
    - Run `searchId=$(az deployment group show --resource-group $rg --name main --query properties.outputs.resources.value.searchService --output tsv)`
    - Run `searchId=$(echo "$searchId" | tr -d '\r')`
    - Run `SEARCH_ENDPOINT=$(az resource show --ids "$searchId" --query "properties.endpoint" --output tsv)`
    - Run `SEARCH_ENDPOINT=$(echo "$SEARCH_ENDPOINT" | tr -d '\r')`
    - Run `API_VERSION="2026-08-01-preview"`
    - Run `EMBEDDING_MODEL_DEPLOYMENT="text-embedding-3-small"`
    - Run `foundryAccountResourceName=$(az deployment group show --resource-group $rg --name main --query properties.outputs.resources.value.foundryAccountResourceName --output tsv)`
    - Run `foundryAccountResourceName=$(echo "$foundryAccountResourceName" | tr -d '\r')`
    - Run `openAIEndpoint="https://${foundryAccountResourceName}.openai.azure.com/"`


## Create the knowledge soure using REST

```
az rest --method put \
  --uri "$SEARCH_ENDPOINT/knowledgesources/ks-contosoproducts?api-version=$API_VERSION" \
  --headers "Authorization=Bearer $search_token" "Content-Type=application/json" \
  --body '{
    "name": "ks-contosoproducts",
    "description": "Blob storage knowledge source for Foundry IQ agentic retrieval",
    "kind": "azureBlob",
    "azureBlobParameters": {
      "connectionString": "'"$BLOB_CONNECTION_STRING"'",
      "containerName": "'"$BLOB_CONTAINER_NAME"'",
      "folderPath": "",
      "isADLSGen2": false,
      "ingestionParameters": {
	"contentExtractionMode": "minimal",
        "disableImageVerbalization": false,
        "ingestionPermissionOptions": [],
        "networkAccessMode": "public",
        "embeddingModel": {
          "kind": "azureOpenAI",
          "azureOpenAIParameters": {
            "resourceUri": "'"$openAIEndpoint"'",
            "deploymentId": "'"$EMBEDDING_MODEL_DEPLOYMENT"'",
            "modelName": "'"$EMBEDDING_MODEL_DEPLOYMENT"'",
	          "apiKey": null
          }
        },
	"chatCompletionModel": {
          "kind": "azureOpenAI",
          "azureOpenAIParameters": {
            "resourceUri": "'"$openAIEndpoint"'",
            "deploymentId": "gpt-5.2",
            "modelName": "gpt-5.2",
	          "apiKey": null
          }
        }
      }
    }
  }'
```

## Create the knowledge base using REST

```
az rest --method put \
  --uri "$SEARCH_ENDPOINT/knowledgebases/knowledgebase576?api-version=$API_VERSION" \
  --headers "Authorization=Bearer $search_token" "Content-Type=application/json" \
  --body '{
    "name": "knowledgebase576",
    "description": "Centralized Foundry IQ Knowledge Base representing unified blob storage data",
    "outputMode": "extractiveData",
    "knowledgeSources": [
      {
        "name": "ks-contosoproducts"
      }
    ],
    "models": [
      {
        "kind": "azureOpenAI",
        "azureOpenAIParameters": {
          "resourceUri": "'"$openAIEndpoint"'",
          "deploymentId": "gpt-5.2",
          "modelName": "gpt-5.2",
          "apiKey": null
        }
      }
    ],
    "retrievalReasoningEffort": {
      "kind": "minimal"
    }
  }'
```