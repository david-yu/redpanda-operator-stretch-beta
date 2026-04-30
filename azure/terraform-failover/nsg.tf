# NSG for the failover node subnet. Mirror the main stack's pattern: one
# rule per port, source includes ALL four VNet CIDRs so it covers same-VNet
# (LB SNAT) and peer-VNet (cross-cluster pod) traffic.
resource "azurerm_network_security_group" "failover" {
  name                = "${var.failover_cluster_name}-nsg"
  location            = var.failover_region
  resource_group_name = azurerm_resource_group.failover.name
  tags                = local.common_tags
}

resource "azurerm_subnet_network_security_group_association" "failover" {
  subnet_id                 = azurerm_subnet.failover_nodes.id
  network_security_group_id = azurerm_network_security_group.failover.id
}

locals {
  failover_port_to_priority = { for idx, p in var.cross_cluster_ports : tostring(p) => 200 + idx * 10 }
  # Priorities for additive rules on existing NSGs — start at 300 to leave
  # space below the main stack's rules (200..240) for any future inserts.
  existing_failover_priority = { for idx, p in var.cross_cluster_ports : tostring(p) => 300 + idx * 10 }
}

resource "azurerm_network_security_rule" "failover" {
  for_each                    = toset([for p in var.cross_cluster_ports : tostring(p)])
  name                        = "rp-stretch-${each.value}"
  priority                    = local.failover_port_to_priority[each.value]
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = each.value
  source_address_prefixes     = local.all_vnet_cidrs
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.failover.name
  network_security_group_name = azurerm_network_security_group.failover.name
}

# --- Additive rules on existing NSGs to allow failover_vnet_cidr as source ---
resource "azurerm_network_security_rule" "east_from_failover" {
  for_each                    = toset([for p in var.cross_cluster_ports : tostring(p)])
  name                        = "rp-stretch-${each.value}-failover"
  priority                    = local.existing_failover_priority[each.value]
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = each.value
  source_address_prefix       = var.failover_vnet_cidr
  destination_address_prefix  = "*"
  resource_group_name         = data.azurerm_resource_group.east.name
  network_security_group_name = data.azurerm_network_security_group.east.name
}

resource "azurerm_network_security_rule" "west_from_failover" {
  for_each                    = toset([for p in var.cross_cluster_ports : tostring(p)])
  name                        = "rp-stretch-${each.value}-failover"
  priority                    = local.existing_failover_priority[each.value]
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = each.value
  source_address_prefix       = var.failover_vnet_cidr
  destination_address_prefix  = "*"
  resource_group_name         = data.azurerm_resource_group.west.name
  network_security_group_name = data.azurerm_network_security_group.west.name
}

resource "azurerm_network_security_rule" "eu_from_failover" {
  for_each                    = toset([for p in var.cross_cluster_ports : tostring(p)])
  name                        = "rp-stretch-${each.value}-failover"
  priority                    = local.existing_failover_priority[each.value]
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = each.value
  source_address_prefix       = var.failover_vnet_cidr
  destination_address_prefix  = "*"
  resource_group_name         = data.azurerm_resource_group.eu.name
  network_security_group_name = data.azurerm_network_security_group.eu.name
}
