# Three regional GKE clusters. All VPC-native (alias IPs), Workload Identity
# enabled, public master endpoint with no master-authorized-networks restriction
# (tighten in production by setting master_authorized_networks_config).

resource "google_container_cluster" "east" {
  name     = local.cluster_name_east
  location = local.region_east

  network    = google_compute_network.vpc.self_link
  subnetwork = google_compute_subnetwork.east.self_link

  release_channel { channel = var.kubernetes_version }

  ip_allocation_policy {
    cluster_secondary_range_name  = google_compute_subnetwork.east.secondary_ip_range[0].range_name
    services_secondary_range_name = google_compute_subnetwork.east.secondary_ip_range[1].range_name
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Disable default node pool, manage explicitly below.
  remove_default_node_pool = true
  initial_node_count       = 1

  deletion_protection = false
}

resource "google_container_node_pool" "east" {
  name     = "default"
  cluster  = google_container_cluster.east.name
  location = local.region_east

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

resource "google_container_cluster" "west" {
  name     = local.cluster_name_west
  location = local.region_west

  network    = google_compute_network.vpc.self_link
  subnetwork = google_compute_subnetwork.west.self_link

  release_channel { channel = var.kubernetes_version }

  ip_allocation_policy {
    cluster_secondary_range_name  = google_compute_subnetwork.west.secondary_ip_range[0].range_name
    services_secondary_range_name = google_compute_subnetwork.west.secondary_ip_range[1].range_name
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = false
}

resource "google_container_node_pool" "west" {
  name     = "default"
  cluster  = google_container_cluster.west.name
  location = local.region_west

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

resource "google_container_cluster" "eu" {
  name     = local.cluster_name_eu
  location = local.region_eu

  network    = google_compute_network.vpc.self_link
  subnetwork = google_compute_subnetwork.eu.self_link

  release_channel { channel = var.kubernetes_version }

  ip_allocation_policy {
    cluster_secondary_range_name  = google_compute_subnetwork.eu.secondary_ip_range[0].range_name
    services_secondary_range_name = google_compute_subnetwork.eu.secondary_ip_range[1].range_name
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = false
}

resource "google_container_node_pool" "eu" {
  name     = "default"
  cluster  = google_container_cluster.eu.name
  location = local.region_eu

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
