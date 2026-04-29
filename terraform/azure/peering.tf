# VNet peering is unidirectional in Azure — each pair needs two peering
# resources (A→B and B→A). With 3 VNets that's 6 peering resources.
# allow_forwarded_traffic + allow_virtual_network_access lets pod traffic
# in one VNet flow to pods in the peered VNet.

resource "azurerm_virtual_network_peering" "east_to_west" {
  name                         = "east-to-west"
  resource_group_name          = azurerm_resource_group.east.name
  virtual_network_name         = azurerm_virtual_network.east.name
  remote_virtual_network_id    = azurerm_virtual_network.west.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "west_to_east" {
  name                         = "west-to-east"
  resource_group_name          = azurerm_resource_group.west.name
  virtual_network_name         = azurerm_virtual_network.west.name
  remote_virtual_network_id    = azurerm_virtual_network.east.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "east_to_eu" {
  name                         = "east-to-eu"
  resource_group_name          = azurerm_resource_group.east.name
  virtual_network_name         = azurerm_virtual_network.east.name
  remote_virtual_network_id    = azurerm_virtual_network.eu.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "eu_to_east" {
  name                         = "eu-to-east"
  resource_group_name          = azurerm_resource_group.eu.name
  virtual_network_name         = azurerm_virtual_network.eu.name
  remote_virtual_network_id    = azurerm_virtual_network.east.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "west_to_eu" {
  name                         = "west-to-eu"
  resource_group_name          = azurerm_resource_group.west.name
  virtual_network_name         = azurerm_virtual_network.west.name
  remote_virtual_network_id    = azurerm_virtual_network.eu.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "eu_to_west" {
  name                         = "eu-to-west"
  resource_group_name          = azurerm_resource_group.eu.name
  virtual_network_name         = azurerm_virtual_network.eu.name
  remote_virtual_network_id    = azurerm_virtual_network.west.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}
