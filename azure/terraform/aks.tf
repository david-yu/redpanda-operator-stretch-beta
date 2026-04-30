# Three AKS clusters, one per region, attached to their local VNet's nodes
# subnet. Azure CNI (overlay or pod-subnet) is required so pod IPs are
# routable across peered VNets — kubenet uses NAT and won't work cross-VNet.

resource "azurerm_kubernetes_cluster" "east" {
  name                = local.cluster_name_east
  location            = local.region_east
  resource_group_name = azurerm_resource_group.east.name
  dns_prefix          = local.cluster_name_east
  kubernetes_version  = var.kubernetes_version
  tags                = local.common_tags

  default_node_pool {
    name            = "default"
    node_count      = var.node_count
    vm_size         = var.vm_size
    os_disk_size_gb = var.node_disk_size_gb
    vnet_subnet_id  = azurerm_subnet.east_nodes.id
    type            = "VirtualMachineScaleSets"
  }

  identity { type = "SystemAssigned" }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    pod_cidr            = var.clusters["east"].pod_cidr
    service_cidr        = var.clusters["east"].service_cidr
    dns_service_ip      = var.clusters["east"].dns_service_ip
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }
}

resource "azurerm_kubernetes_cluster" "west" {
  name                = local.cluster_name_west
  location            = local.region_west
  resource_group_name = azurerm_resource_group.west.name
  dns_prefix          = local.cluster_name_west
  kubernetes_version  = var.kubernetes_version
  tags                = local.common_tags

  default_node_pool {
    name            = "default"
    node_count      = var.node_count
    vm_size         = var.vm_size
    os_disk_size_gb = var.node_disk_size_gb
    vnet_subnet_id  = azurerm_subnet.west_nodes.id
    type            = "VirtualMachineScaleSets"
  }

  identity { type = "SystemAssigned" }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    pod_cidr            = var.clusters["west"].pod_cidr
    service_cidr        = var.clusters["west"].service_cidr
    dns_service_ip      = var.clusters["west"].dns_service_ip
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }
}

resource "azurerm_kubernetes_cluster" "eu" {
  name                = local.cluster_name_eu
  location            = local.region_eu
  resource_group_name = azurerm_resource_group.eu.name
  dns_prefix          = local.cluster_name_eu
  kubernetes_version  = var.kubernetes_version
  tags                = local.common_tags

  default_node_pool {
    name            = "default"
    node_count      = var.node_count
    vm_size         = var.vm_size
    os_disk_size_gb = var.node_disk_size_gb
    vnet_subnet_id  = azurerm_subnet.eu_nodes.id
    type            = "VirtualMachineScaleSets"
  }

  identity { type = "SystemAssigned" }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    pod_cidr            = var.clusters["eu"].pod_cidr
    service_cidr        = var.clusters["eu"].service_cidr
    dns_service_ip      = var.clusters["eu"].dns_service_ip
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }
}
