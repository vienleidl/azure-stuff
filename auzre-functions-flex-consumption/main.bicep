// Parameters
@description('The location of the resources.')
param location string = resourceGroup().location

@description('The name of the Function App.')
param functionAppName string

@description('The runtime stack for the Function App.')
param runtimeName string = 'dotnet-isolated'

@description('The runtime version for the Function App.')
param runtimeVersion string = '8.0'

@description('The memory allocated for each instance in megabytes.')
param instanceMemoryMB int = 2048

@description('The maximum number of instances.')
param maximumInstanceCount int = 40

@description('The name of the App Service plan.')
param appServicePlanName string

@description('The SKU tier of the App Service plan.')
param appServicePlanSkuTier string = 'FlexConsumption'

@description('The SKU name of the App Service plan.')
param appServicePlanSkuName string = 'FC1'

@description('The name of the existing Virtual Network.')
param existingVnetName  string

@description('The resource group of the existing Virtual Network.')
param vnetResourceGroupName string

@description('The name of the new subnet.')
param newSubnetName string

@description('The address prefix for the new subnet.')
param newSubnetAddressPrefix string = '10.1.1.0/26'

@description('The name of the Storage Account.')
param storageAccountName string

@description('The type of the Storage Account.')
param storageAccountType string = 'Standard_LRS'

@description('The access tier for the Storage Account.')
param accessTier string = 'Hot'

@description('Allow or disallow public access to blobs.')
param allowBlobPublicAccess bool = false

@description('The kind of Storage Account.')
param kind string = 'StorageV2'

@description('The name of the Log Analytics workspace.')
param logAnalyticsWorkspaceName string

@description('The name of the Key Vault.')
param keyVaultName string

@description('Enable or disable Key Vault for deployment.')
param enableVaultForDeployment bool = true

@description('Enable or disable Key Vault for template deployment.')
param enableVaultForTemplateDeployment bool = true

@description('Enable or disable Key Vault for disk encryption.')
param enableVaultForDiskEncryption bool = false

@description('Enable or disable soft delete for Key Vault.')
param enableSoftDelete bool = true

@description('The number of days to retain soft deleted items in Key Vault.')
param softDeleteRetentionInDays int = 90

@description('Enable or disable RBAC authorization for Key Vault.')
param enableRbacAuthorization bool = true

@description('The create mode for Key Vault.')
param createMode string = 'default'

@description('Enable or disable purge protection for Key Vault.')
param enablePurgeProtection bool = true

@description('The SKU for Key Vault.')
param sku string = 'standard'

// Variables
@description('Optional. Resource tags.')
var tags  = {
  landscape: 'production'
  module: 'devops'
}

@description('The name of the Application Insights resource, derived from the Function App name.')
var appInsightsName = functionAppName

@description('Generate a unique token to be used in naming resources.')
var resourceToken = toLower(uniqueString(subscription().id, location))

@description('Generate a unique container name that will be used for deployments.')
var deploymentStorageContainerName = 'app-package-${take(functionAppName, 32)}-${take(toLower(uniqueString(functionAppName, resourceToken)), 7)}'

@description('The containers for the storage account.')
var containers = [
  {
    name: deploymentStorageContainerName
    publicAccess: 'None'
  }
  {
    name: 'logs'
    publicAccess: 'None'
  }
]

@description('The resource ID of the new subnet.')
var subnetResourceId = resourceId(vnetResourceGroupName, 'Microsoft.Network/virtualNetworks/subnets', existingVnetName, newSubnetName)

// Resources Deployment

// Subnet
module subnet './subnetModule.bicep' = {
  name: newSubnetName
  scope: resourceGroup(vnetResourceGroupName)
  params: {
    existingVnetName: existingVnetName
    newSubnetName: newSubnetName
    newSubnetAddressPrefix: newSubnetAddressPrefix
  }
}

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: keyVaultName
  location: location
  dependsOn: [
    subnet
  ]
  tags: union(tags, {
    'ms-resource-usage': 'azure-key-vault'
  })
  properties: {
    enabledForDeployment: enableVaultForDeployment
    enabledForTemplateDeployment: enableVaultForTemplateDeployment
    enabledForDiskEncryption: enableVaultForDiskEncryption
    enableSoftDelete: enableSoftDelete
    softDeleteRetentionInDays: softDeleteRetentionInDays
    enableRbacAuthorization: enableRbacAuthorization
    createMode: createMode
    enablePurgeProtection: enablePurgeProtection ? enablePurgeProtection : null
    tenantId: subscription().tenantId
    sku: {
      name: sku
      family: 'A'
    }
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      virtualNetworkRules: [
        {
          id: subnetResourceId
        }
      ]
    }
  }
}

// Storage account for function package
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  dependsOn: [
    subnet
  ]
  tags: union(tags, {
    'ms-resource-usage': 'azure-storage-account'
  })
  sku: {
    name: storageAccountType
  }
  kind: kind
  properties: {
    accessTier: accessTier
    allowBlobPublicAccess: allowBlobPublicAccess
    supportsHttpsTrafficOnly: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      virtualNetworkRules: [
        {
          id: subnetResourceId
        }
      ]
    }
  }
  resource blobServices 'blobServices' = if (!empty(containers)) {
    name: 'default'
    properties: {
      deleteRetentionPolicy: {
        enabled: true
        days: 35
      }
      containerDeleteRetentionPolicy: {
        enabled: true
        days: 35
      }
    }
    resource container 'containers' = [for container in containers: {
      name: container.name
      properties: {
        publicAccess: container.publicAccess
      }
    }]
  }
}

// Lifecycle management policy
resource managementPolicy 'Microsoft.Storage/storageAccounts/managementPolicies@2021-09-01' = {
  name: 'default'
  parent: storageAccount
  properties: {
    policy: {
      rules: [
        {
          enabled: true
          name: 'delete-logs-aftermodificationgreaterthan30days'
          type: 'Lifecycle'
          definition: {
            actions: {
              baseBlob: {
                delete: {
                  daysAfterModificationGreaterThan: 30
                }
              }
            }
            filters: {
              blobTypes: [
                'appendBlob'
                'blockBlob'
              ]
              prefixMatch: [
                'logs'
              ]
            }
          }
        }
        {
          enabled: true
          name: 'delete-webjoblogs-aftermodificationgreaterthan30days'
          type: 'Lifecycle'
          definition: {
            actions: {
              baseBlob: {
                delete: {
                  daysAfterModificationGreaterThan: 30
                }
              }
            }
            filters: {
              blobTypes: [
                'blockBlob'
              ]
              prefixMatch: [
                'azure-jobs-host-archive'
                'azure-jobs-host-output'
                'azure-webjobs-dashboard/functions/instances'
                'azure-webjobs-dashboard/functions/recent'
                'azure-webjobs-hosts/output-logs'
              ]
            }
          }
        }
      ]
    }
  }
}

// Log Analytics workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: union(tags, {
    'ms-resource-usage': 'azure-log-analytics'
  })
  properties: {
    sku: {
      name: 'standalone'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: 2
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: union(tags, {
    'ms-resource-usage': 'azure-app-insights'
  })
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

// App Service plan
resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: appServicePlanName
  location: location
  tags: union(tags, {
    'ms-resource-usage': 'azure-app-service-plan'
  })
  sku: {
    tier: appServicePlanSkuTier
    name: appServicePlanSkuName
  }
  properties: {
    reserved: true
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  dependsOn: [
    subnet
  ]
  tags: union(tags, {
    'ms-resource-usage': 'azure-function-app'
  })
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    reserved: true
    serverFarmId: appServicePlan.id
    siteConfig: {
      appSettings: [
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }
        { name: 'AzureWebJobsStorage__accountname', value: storageAccountName }
        { name: 'AzureFunctionsJobHost__Logging__ApplicationInsights__LogLevel__Default', value: 'Warning' }
        { name: 'AzureFunctionsJobHost__Logging__Console__LogLevel__Default', value: 'Warning' }
        { name: 'AzureFunctionsJobHost__Logging__Debug__LogLevel__Default', value: 'Warning' }
        { name: 'AzureFunctionsJobHost__Logging__LogLevel__Default', value: 'Warning' }
      ]
    }
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storageAccount.properties.primaryEndpoints.blob}${deploymentStorageContainerName}'
          authentication: {
            type: 'SystemAssignedIdentity' 
          }
        }
      }
      scaleAndConcurrency: {
        instanceMemoryMB: instanceMemoryMB
        maximumInstanceCount: maximumInstanceCount
      }
      runtime: {
        name: runtimeName
        version: runtimeVersion
      }
    }
    virtualNetworkSubnetId: subnetResourceId
  }
}

// Outputs
output functionName string = functionApp.name
output functionAppHostName string = functionApp.properties.defaultHostName
output functionAppId string = functionApp.id
output functionAppState string = functionApp.properties.state
output functionAppDefaultHostName string = functionApp.properties.defaultHostName
output functionAppOutboundIpAddresses string = functionApp.properties.outboundIpAddresses
output functionAppPossibleOutboundIpAddresses string = functionApp.properties.possibleOutboundIpAddresses
output functionAppResourceGroup string = functionApp.properties.resourceGroup
output location string = functionApp.location
output resourceGroupName string = resourceGroup().name
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output logAnalyticsWorkspaceResourceId string = logAnalyticsWorkspace.id
output storageAccountName string = storageAccount.name
output storageAccountResourceId string = storageAccount.id
output keyVaultName string = keyVault.name
output keyVaultResourceId string = keyVault.id
