@description('Optional. The Name of the subnet resource.')
param newSubnetName string

@description('Required. The address prefix for the subnet.')
param newSubnetAddressPrefix string

@description('Name of the VNET to add a subnet to')
param existingVnetName string

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-01-01' existing = {
  name: existingVnetName
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' = {
  name: newSubnetName
  parent: virtualNetwork
  properties: {
    addressPrefix: newSubnetAddressPrefix
    serviceEndpoints: [ 
      {
        service: 'Microsoft.Storage'
      }
      {
        service: 'Microsoft.KeyVault'
      }
    ]
    delegations: [
      {
        name: 'delegation'
        properties: {
          serviceName: 'Microsoft.App/environments'
        }
      }
    ]
  }
}

@description('The resource group the virtual network peering was deployed into.')
output resourceGroupName string = resourceGroup().name

@description('The name of the virtual network peering.')
output vnet string = virtualNetwork.name

@description('The name of the virtual network peering.')
output name string = subnet.name

@description('The resource ID of the virtual network peering.')
output resourceId string = subnet.id

@description('The address prefix for the subnet.')
output subnetAddressPrefix string = subnet.properties.addressPrefix
