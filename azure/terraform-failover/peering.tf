# VNet peering — six new peering resources to extend the main stack's
# 3-region full mesh to a 4-region full mesh. Azure VNet peering is
# unidirectional, so each pair (failover ↔ existing) needs two resources.
# allow_forwarded_traffic + allow_virtual_network_access lets pod traffic
# in one VNet flow to pods in the peered VNet.

resource "azurerm_virtual_network_peering" "failover_to_east" {
  name                         = "failover-to-east"
  resource_group_name          = azurerm_resource_group.failover.name
  virtual_network_name         = azurerm_virtual_network.failover.name
  remote_virtual_network_id    = data.azurerm_virtual_network.east.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "east_to_failover" {
  name                         = "east-to-failover"
  resource_group_name          = data.azurerm_resource_group.east.name
  virtual_network_name         = data.azurerm_virtual_network.east.name
  remote_virtual_network_id    = azurerm_virtual_network.failover.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "failover_to_west" {
  name                         = "failover-to-west"
  resource_group_name          = azurerm_resource_group.failover.name
  virtual_network_name         = azurerm_virtual_network.failover.name
  remote_virtual_network_id    = data.azurerm_virtual_network.west.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "west_to_failover" {
  name                         = "west-to-failover"
  resource_group_name          = data.azurerm_resource_group.west.name
  virtual_network_name         = data.azurerm_virtual_network.west.name
  remote_virtual_network_id    = azurerm_virtual_network.failover.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "failover_to_eu" {
  name                         = "failover-to-eu"
  resource_group_name          = azurerm_resource_group.failover.name
  virtual_network_name         = azurerm_virtual_network.failover.name
  remote_virtual_network_id    = data.azurerm_virtual_network.eu.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "eu_to_failover" {
  name                         = "eu-to-failover"
  resource_group_name          = data.azurerm_resource_group.eu.name
  virtual_network_name         = data.azurerm_virtual_network.eu.name
  remote_virtual_network_id    = azurerm_virtual_network.failover.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}
