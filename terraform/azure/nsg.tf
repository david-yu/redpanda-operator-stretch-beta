# NSG rules attached to each cluster's node subnet. Allow ingress on the
# stretch-cluster ports from any peer VNet CIDR (for cross-cluster pod
# traffic over VNet peering) plus the local VNet CIDR (for the internal
# Standard LB which SNATs to LB frontend IPs).

resource "azurerm_network_security_group" "east" {
  name                = "${local.cluster_name_east}-nsg"
  location            = local.region_east
  resource_group_name = azurerm_resource_group.east.name
  tags                = local.common_tags
}

resource "azurerm_network_security_group" "west" {
  name                = "${local.cluster_name_west}-nsg"
  location            = local.region_west
  resource_group_name = azurerm_resource_group.west.name
  tags                = local.common_tags
}

resource "azurerm_network_security_group" "eu" {
  name                = "${local.cluster_name_eu}-nsg"
  location            = local.region_eu
  resource_group_name = azurerm_resource_group.eu.name
  tags                = local.common_tags
}

resource "azurerm_subnet_network_security_group_association" "east" {
  subnet_id                 = azurerm_subnet.east_nodes.id
  network_security_group_id = azurerm_network_security_group.east.id
}

resource "azurerm_subnet_network_security_group_association" "west" {
  subnet_id                 = azurerm_subnet.west_nodes.id
  network_security_group_id = azurerm_network_security_group.west.id
}

resource "azurerm_subnet_network_security_group_association" "eu" {
  subnet_id                 = azurerm_subnet.eu_nodes.id
  network_security_group_id = azurerm_network_security_group.eu.id
}

# One rule per (cluster, port) — uses all three VNet CIDRs as source so the
# rule covers same-VNet (LB SNAT) and peer-VNet (cross-cluster pod) traffic.
locals {
  port_to_priority = { for idx, p in var.cross_cluster_ports : tostring(p) => 200 + idx * 10 }
}

resource "azurerm_network_security_rule" "east" {
  for_each                    = toset([for p in var.cross_cluster_ports : tostring(p)])
  name                        = "rp-stretch-${each.value}"
  priority                    = local.port_to_priority[each.value]
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = each.value
  source_address_prefixes     = local.all_vnet_cidrs
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.east.name
  network_security_group_name = azurerm_network_security_group.east.name
}

resource "azurerm_network_security_rule" "west" {
  for_each                    = toset([for p in var.cross_cluster_ports : tostring(p)])
  name                        = "rp-stretch-${each.value}"
  priority                    = local.port_to_priority[each.value]
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = each.value
  source_address_prefixes     = local.all_vnet_cidrs
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.west.name
  network_security_group_name = azurerm_network_security_group.west.name
}

resource "azurerm_network_security_rule" "eu" {
  for_each                    = toset([for p in var.cross_cluster_ports : tostring(p)])
  name                        = "rp-stretch-${each.value}"
  priority                    = local.port_to_priority[each.value]
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = each.value
  source_address_prefixes     = local.all_vnet_cidrs
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.eu.name
  network_security_group_name = azurerm_network_security_group.eu.name
}
