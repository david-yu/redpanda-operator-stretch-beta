output "failover_cluster_name" {
  description = "Name of the failover GKE cluster (also the kubectl context alias after rename)."
  value       = var.failover_cluster_name
}

output "failover_region" {
  description = "Region where the failover cluster was created."
  value       = var.failover_region
}

output "failover_gke_endpoint" {
  description = "Failover cluster control plane endpoint — paste into the rp-failover helm values' multicluster.apiServerExternalAddress."
  value       = "https://${google_container_cluster.failover.endpoint}"
}

output "failover_peer_lb_address" {
  description = "Internal LB IP for the failover peer Service — add to the multicluster.peers list in every cluster's helm values."
  value       = try(data.kubernetes_service.peer_failover.status[0].load_balancer[0].ingress[0].ip, "")
}

output "failover_kubectl_setup_command" {
  description = "Run this to register the failover cluster as a kubectl context aliased `rp-failover` (or your override)."
  value       = <<-EOT
    gcloud container clusters get-credentials ${var.failover_cluster_name} --region ${var.failover_region} --project ${var.project_id}
    kubectl config rename-context gke_${var.project_id}_${var.failover_region}_${var.failover_cluster_name} ${var.failover_cluster_name}
  EOT
}
