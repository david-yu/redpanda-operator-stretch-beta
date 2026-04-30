# Each AKS cluster runs with a system-assigned identity. When the cluster uses
# a BYO VNet (our case — the VNet/subnet are managed by terraform separately
# from the cluster), the identity has no implicit permission on the VNet. The
# AKS cloud-controller-manager needs `Microsoft.Network/virtualNetworks/
# subnets/read` to provision a LoadBalancer Service, so without this role
# assignment the operator peer LB Service stays Pending forever with
# "AuthorizationFailed: ... does not have authorization to perform action
# 'Microsoft.Network/virtualNetworks/subnets/read' ...".
#
# Network Contributor on the subnet is the standard scope.

resource "azurerm_role_assignment" "aks_east_subnet" {
  scope                = azurerm_subnet.east_nodes.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.east.identity[0].principal_id
}

resource "azurerm_role_assignment" "aks_west_subnet" {
  scope                = azurerm_subnet.west_nodes.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.west.identity[0].principal_id
}

resource "azurerm_role_assignment" "aks_eu_subnet" {
  scope                = azurerm_subnet.eu_nodes.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.eu.identity[0].principal_id
}
