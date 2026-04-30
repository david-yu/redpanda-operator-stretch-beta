output "cluster_names" {
  description = "Cluster names per region — also used as kubectl context aliases."
  value = {
    east = local.cluster_name_east
    west = local.cluster_name_west
    eu   = local.cluster_name_eu
  }
}

output "regions" {
  description = "Regions per cluster — pass to az aks get-credentials."
  value = {
    east = local.region_east
    west = local.region_west
    eu   = local.region_eu
  }
}

output "aks_endpoints" {
  description = "AKS API server endpoints — paste into multicluster.apiServerExternalAddress in helm values."
  # `kube_config` blocks are flagged sensitive by the azurerm provider because
  # they wrap credentials, but the API host URL alone isn't a secret — it's
  # derivable from `<cluster>.<region>.azmk8s.io` and we surface it for users
  # to paste into helm values. nonsensitive() unwraps just the host string.
  value = {
    east = nonsensitive(azurerm_kubernetes_cluster.east.kube_config[0].host)
    west = nonsensitive(azurerm_kubernetes_cluster.west.kube_config[0].host)
    eu   = nonsensitive(azurerm_kubernetes_cluster.eu.kube_config[0].host)
  }
}

output "peer_lb_addresses" {
  description = "Internal LB IPs for the pre-created peer Services — paste into multicluster.peers in helm values."
  value = {
    east = try(data.kubernetes_service.peer_east.status[0].load_balancer[0].ingress[0].ip, "")
    west = try(data.kubernetes_service.peer_west.status[0].load_balancer[0].ingress[0].ip, "")
    eu   = try(data.kubernetes_service.peer_eu.status[0].load_balancer[0].ingress[0].ip, "")
  }
}

output "kubectl_setup_commands" {
  description = "Run these to add each cluster's context to your local kubeconfig with short alias names."
  value       = <<-EOT
    az aks get-credentials --name ${local.cluster_name_east} --resource-group ${azurerm_resource_group.east.name} --context ${local.cluster_name_east} --overwrite-existing
    az aks get-credentials --name ${local.cluster_name_west} --resource-group ${azurerm_resource_group.west.name} --context ${local.cluster_name_west} --overwrite-existing
    az aks get-credentials --name ${local.cluster_name_eu}   --resource-group ${azurerm_resource_group.eu.name}   --context ${local.cluster_name_eu}   --overwrite-existing
  EOT
}
