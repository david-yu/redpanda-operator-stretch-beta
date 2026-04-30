resource "azurerm_resource_group" "failover" {
  name     = "${var.failover_cluster_name}-rg"
  location = var.failover_region
  tags     = local.common_tags
}

resource "azurerm_virtual_network" "failover" {
  name                = "${var.failover_cluster_name}-vnet"
  resource_group_name = azurerm_resource_group.failover.name
  location            = var.failover_region
  address_space       = [var.failover_vnet_cidr]
  tags                = local.common_tags
}

resource "azurerm_subnet" "failover_nodes" {
  name                 = "nodes"
  resource_group_name  = azurerm_resource_group.failover.name
  virtual_network_name = azurerm_virtual_network.failover.name
  address_prefixes     = [var.failover_subnet_cidr]
}
