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

  # Traditional Azure CNI (no overlay) so pod IPs come from the VNet subnet
  # and route across peered VNets — overlay-mode VXLAN encapsulation breaks
  # cross-cluster pod IP traffic that Redpanda's flat mode requires.
  network_profile {
    network_plugin    = "azure"
    service_cidr      = var.failover_service_cidr
    dns_service_ip    = var.failover_dns_service_ip
    load_balancer_sku = "standard"
    outbound_type     = "loadBalancer"
  }
}

# Network Contributor on the failover subnet so the AKS cloud-controller can
# provision LoadBalancer Services in the BYO VNet — without this, the peer
# Service stays Pending with AuthorizationFailed and finalizer-based cleanup
# at delete time hangs.
resource "azurerm_role_assignment" "aks_failover_subnet" {
  scope                = azurerm_subnet.failover_nodes.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.failover.identity[0].principal_id
}
