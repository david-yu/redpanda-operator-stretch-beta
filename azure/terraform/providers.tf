provider "azurerm" {
  features {}
}

# Kubernetes providers per cluster — exec auth via kubelogin (Azure AD) or
# the cluster's local admin kubeconfig (used here for simplicity).

provider "kubernetes" {
  alias                  = "east"
  host                   = azurerm_kubernetes_cluster.east.kube_admin_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.east.kube_admin_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.east.kube_admin_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.east.kube_admin_config[0].cluster_ca_certificate)
}

provider "kubernetes" {
  alias                  = "west"
  host                   = azurerm_kubernetes_cluster.west.kube_admin_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.west.kube_admin_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.west.kube_admin_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.west.kube_admin_config[0].cluster_ca_certificate)
}

provider "kubernetes" {
  alias                  = "eu"
  host                   = azurerm_kubernetes_cluster.eu.kube_admin_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.eu.kube_admin_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.eu.kube_admin_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.eu.kube_admin_config[0].cluster_ca_certificate)
}
