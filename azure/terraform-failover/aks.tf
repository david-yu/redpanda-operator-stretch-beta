resource "azurerm_kubernetes_cluster" "failover" {
  name                = var.failover_cluster_name
  location            = var.failover_region
  resource_group_name = azurerm_resource_group.failover.name
  dns_prefix          = var.failover_cluster_name
  kubernetes_version  = var.kubernetes_version
  tags                = local.common_tags

  default_node_pool {
    name            = "default"
    node_count      = var.node_count
    vm_size         = var.vm_size
    os_disk_size_gb = var.node_disk_size_gb
    vnet_subnet_id  = azurerm_subnet.failover_nodes.id
    type            = "VirtualMachineScaleSets"
  }

  identity { type = "SystemAssigned" }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    pod_cidr            = var.failover_pod_cidr
    service_cidr        = var.failover_service_cidr
    dns_service_ip      = var.failover_dns_service_ip
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }
}
