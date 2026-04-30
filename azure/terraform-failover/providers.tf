# Single azurerm provider — Azure providers don't need region aliasing
# (each resource takes its own `location`/`resource_group_name`). The main
# stack's azurerm provider is unaffected.

provider "azurerm" {
  features {}
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.failover.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.failover.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.failover.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.failover.kube_config[0].cluster_ca_certificate)
}
