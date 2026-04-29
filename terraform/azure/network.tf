# Three resource groups, three VNets (Azure VNets are regional), one node
# subnet per VNet. Peering is in peering.tf.

resource "azurerm_resource_group" "east" {
  name     = "${local.cluster_name_east}-rg"
  location = local.region_east
  tags     = local.common_tags
}

resource "azurerm_resource_group" "west" {
  name     = "${local.cluster_name_west}-rg"
  location = local.region_west
  tags     = local.common_tags
}

resource "azurerm_resource_group" "eu" {
  name     = "${local.cluster_name_eu}-rg"
  location = local.region_eu
  tags     = local.common_tags
}

resource "azurerm_virtual_network" "east" {
  name                = "${local.cluster_name_east}-vnet"
  resource_group_name = azurerm_resource_group.east.name
  location            = local.region_east
  address_space       = [var.clusters["east"].vnet_cidr]
  tags                = local.common_tags
}

resource "azurerm_virtual_network" "west" {
  name                = "${local.cluster_name_west}-vnet"
  resource_group_name = azurerm_resource_group.west.name
  location            = local.region_west
  address_space       = [var.clusters["west"].vnet_cidr]
  tags                = local.common_tags
}

resource "azurerm_virtual_network" "eu" {
  name                = "${local.cluster_name_eu}-vnet"
  resource_group_name = azurerm_resource_group.eu.name
  location            = local.region_eu
  address_space       = [var.clusters["eu"].vnet_cidr]
  tags                = local.common_tags
}

resource "azurerm_subnet" "east_nodes" {
  name                 = "nodes"
  resource_group_name  = azurerm_resource_group.east.name
  virtual_network_name = azurerm_virtual_network.east.name
  address_prefixes     = [var.clusters["east"].subnet_cidr]
}

resource "azurerm_subnet" "west_nodes" {
  name                 = "nodes"
  resource_group_name  = azurerm_resource_group.west.name
  virtual_network_name = azurerm_virtual_network.west.name
  address_prefixes     = [var.clusters["west"].subnet_cidr]
}

resource "azurerm_subnet" "eu_nodes" {
  name                 = "nodes"
  resource_group_name  = azurerm_resource_group.eu.name
  virtual_network_name = azurerm_virtual_network.eu.name
  address_prefixes     = [var.clusters["eu"].subnet_cidr]
}
