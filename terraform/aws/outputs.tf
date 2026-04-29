output "cluster_names" {
  description = "Cluster names per region — also used as kubectl context names by aws eks update-kubeconfig --alias <name>."
  value = {
    east = local.cluster_name_east
    west = local.cluster_name_west
    eu   = local.cluster_name_eu
  }
}

output "regions" {
  description = "Regions per cluster — pass to aws eks update-kubeconfig."
  value = {
    east = local.region_east
    west = local.region_west
    eu   = local.region_eu
  }
}

output "eks_endpoints" {
  description = "EKS API server endpoints — paste into multicluster.apiServerExternalAddress in helm values."
  value = {
    east = module.eks_east.cluster_endpoint
    west = module.eks_west.cluster_endpoint
    eu   = module.eks_eu.cluster_endpoint
  }
}

output "peer_lb_hostnames" {
  description = "NLB hostnames for the pre-created peer Services — paste into multicluster.peers in helm values."
  value = {
    east = try(data.kubernetes_service.peer_east.status[0].load_balancer[0].ingress[0].hostname, "")
    west = try(data.kubernetes_service.peer_west.status[0].load_balancer[0].ingress[0].hostname, "")
    eu   = try(data.kubernetes_service.peer_eu.status[0].load_balancer[0].ingress[0].hostname, "")
  }
}

output "kubectl_setup_commands" {
  description = "Run these to add each cluster's context to your local kubeconfig with short alias names."
  value = <<-EOT
    aws eks update-kubeconfig --region ${local.region_east} --name ${local.cluster_name_east} --alias ${local.cluster_name_east}
    aws eks update-kubeconfig --region ${local.region_west} --name ${local.cluster_name_west} --alias ${local.cluster_name_west}
    aws eks update-kubeconfig --region ${local.region_eu}   --name ${local.cluster_name_eu}   --alias ${local.cluster_name_eu}
  EOT
}
