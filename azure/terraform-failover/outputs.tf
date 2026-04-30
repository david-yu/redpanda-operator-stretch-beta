output "failover_cluster_name" {
  description = "Name of the failover AKS cluster (also the kubectl context alias after rename)."
  value       = var.failover_cluster_name
}

output "failover_region" {
  description = "Region where the failover cluster was created."
  value       = var.failover_region
}

output "failover_aks_fqdn" {
  description = "Failover AKS API FQDN — prefix with https:// and paste into multicluster.apiServerExternalAddress."
  value       = azurerm_kubernetes_cluster.failover.fqdn
}

output "failover_peer_lb_address" {
  description = "Internal LB IP for the failover peer Service — add to multicluster.peers in every cluster's helm values."
  value       = try(data.kubernetes_service.peer_failover.status[0].load_balancer[0].ingress[0].ip, "")
}

output "failover_kubectl_setup_command" {
  description = "Run this to register the failover cluster as a kubectl context aliased rp-failover."
  value       = <<-EOT
    az aks get-credentials --resource-group ${azurerm_resource_group.failover.name} --name ${var.failover_cluster_name} --context ${var.failover_cluster_name} --overwrite-existing
  EOT
}
