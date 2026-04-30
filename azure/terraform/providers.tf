provider "azurerm" {
  features {}
}

# Kubernetes providers per cluster — uses the local-account kubeconfig
# (`kube_config`). `kube_admin_config` is only populated when the cluster has
# Entra ID (Azure AD) admin enabled, which we don't do here, so referencing
# kube_admin_config[0] errors with "Invalid index" against the empty list.

provider "kubernetes" {
  alias                  = "east"
  host                   = azurerm_kubernetes_cluster.east.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.east.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.east.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.east.kube_config[0].cluster_ca_certificate)
}

provider "kubernetes" {
  alias                  = "west"
  host                   = azurerm_kubernetes_cluster.west.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.west.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.west.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.west.kube_config[0].cluster_ca_certificate)
}

provider "kubernetes" {
  alias                  = "eu"
  host                   = azurerm_kubernetes_cluster.eu.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.eu.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.eu.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.eu.kube_config[0].cluster_ca_certificate)
}
