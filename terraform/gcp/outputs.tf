output "cluster_names" {
  description = "Cluster names per region — also used as kubectl context aliases."
  value = {
    east = local.cluster_name_east
    west = local.cluster_name_west
    eu   = local.cluster_name_eu
  }
}

output "regions" {
  description = "Regions per cluster — pass to gcloud container clusters get-credentials."
  value = {
    east = local.region_east
    west = local.region_west
    eu   = local.region_eu
  }
}

output "gke_endpoints" {
  description = "GKE control plane endpoints — paste into multicluster.apiServerExternalAddress in helm values."
  value = {
    east = "https://${google_container_cluster.east.endpoint}"
    west = "https://${google_container_cluster.west.endpoint}"
    eu   = "https://${google_container_cluster.eu.endpoint}"
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
    gcloud container clusters get-credentials ${local.cluster_name_east} --region ${local.region_east} --project ${var.project_id}
    kubectl config rename-context gke_${var.project_id}_${local.region_east}_${local.cluster_name_east} ${local.cluster_name_east}
    gcloud container clusters get-credentials ${local.cluster_name_west} --region ${local.region_west} --project ${var.project_id}
    kubectl config rename-context gke_${var.project_id}_${local.region_west}_${local.cluster_name_west} ${local.cluster_name_west}
    gcloud container clusters get-credentials ${local.cluster_name_eu} --region ${local.region_eu} --project ${var.project_id}
    kubectl config rename-context gke_${var.project_id}_${local.region_eu}_${local.cluster_name_eu} ${local.cluster_name_eu}
  EOT
}
