output "failover_cluster_name" {
  description = "Name of the failover EKS cluster (also the kubectl context alias after rename)."
  value       = var.failover_cluster_name
}

output "failover_region" {
  description = "Region where the failover cluster was created."
  value       = var.failover_region
}

output "failover_eks_endpoint" {
  description = "Failover cluster API endpoint — paste into rp-failover helm values' multicluster.apiServerExternalAddress."
  value       = module.eks_failover.cluster_endpoint
}

output "failover_peer_lb_hostname" {
  description = "NLB DNS name for the failover peer Service — add to multicluster.peers in every cluster's helm values."
  value       = try(data.kubernetes_service.peer_failover.status[0].load_balancer[0].ingress[0].hostname, "")
}

output "failover_kubectl_setup_command" {
  description = "Run this to register the failover cluster as a kubectl context aliased rp-failover."
  value       = <<-EOT
    aws eks update-kubeconfig --region ${var.failover_region} --name ${var.failover_cluster_name} --alias ${var.failover_cluster_name}
  EOT
}
