# Look up the main stack's resource groups, VNets, and NSGs by name. The
# main stack names them deterministically as `<cluster-name>-rg/-vnet/-nsg`,
# so we can find them without remote_state.

data "azurerm_resource_group" "east" {
  name = "${var.existing_clusters["east"].name}-rg"
}

data "azurerm_resource_group" "west" {
  name = "${var.existing_clusters["west"].name}-rg"
}

data "azurerm_resource_group" "eu" {
  name = "${var.existing_clusters["eu"].name}-rg"
}

data "azurerm_virtual_network" "east" {
  name                = "${var.existing_clusters["east"].name}-vnet"
  resource_group_name = data.azurerm_resource_group.east.name
}

data "azurerm_virtual_network" "west" {
  name                = "${var.existing_clusters["west"].name}-vnet"
  resource_group_name = data.azurerm_resource_group.west.name
}

data "azurerm_virtual_network" "eu" {
  name                = "${var.existing_clusters["eu"].name}-vnet"
  resource_group_name = data.azurerm_resource_group.eu.name
}

data "azurerm_network_security_group" "east" {
  name                = "${var.existing_clusters["east"].name}-nsg"
  resource_group_name = data.azurerm_resource_group.east.name
}

data "azurerm_network_security_group" "west" {
  name                = "${var.existing_clusters["west"].name}-nsg"
  resource_group_name = data.azurerm_resource_group.west.name
}

data "azurerm_network_security_group" "eu" {
  name                = "${var.existing_clusters["eu"].name}-nsg"
  resource_group_name = data.azurerm_resource_group.eu.name
}
