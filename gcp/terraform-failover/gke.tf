resource "google_container_cluster" "failover" {
  name     = var.failover_cluster_name
  location = var.failover_region

  network    = data.google_compute_network.vpc.self_link
  subnetwork = google_compute_subnetwork.failover.self_link

  release_channel { channel = var.kubernetes_version }

  ip_allocation_policy {
    cluster_secondary_range_name  = google_compute_subnetwork.failover.secondary_ip_range[0].range_name
    services_secondary_range_name = google_compute_subnetwork.failover.secondary_ip_range[1].range_name
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  remove_default_node_pool = true
  initial_node_count       = 1

  deletion_protection = false
}

resource "google_container_node_pool" "failover" {
  name     = "default"
  cluster  = google_container_cluster.failover.name
  location = var.failover_region

  node_count = var.node_count

  node_config {
    machine_type = var.machine_type
    disk_size_gb = var.node_disk_size_gb
    disk_type    = "pd-balanced"

    workload_metadata_config { mode = "GKE_METADATA" }

    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
    labels       = local.common_labels
  }
}
