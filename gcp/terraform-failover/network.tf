# Look up the existing global VPC by the name the main stack created
# (`<project_name>-vpc`). GCP VPCs are global, so the failover region's
# subnet attaches to the same VPC and gets pod-to-pod connectivity to all
# three existing regions for free.
data "google_compute_network" "vpc" {
  name = "${var.project_name}-vpc"
}

resource "google_compute_subnetwork" "failover" {
  name          = "${var.failover_cluster_name}-subnet"
  region        = var.failover_region
  network       = data.google_compute_network.vpc.id
  ip_cidr_range = var.failover_subnet_cidr

  secondary_ip_range {
    range_name    = "${var.failover_cluster_name}-pods"
    ip_cidr_range = var.failover_pods_cidr
  }
  secondary_ip_range {
    range_name    = "${var.failover_cluster_name}-services"
    ip_cidr_range = var.failover_services_cidr
  }

  private_ip_google_access = true
}

# Cloud Router + NAT for outbound internet from the failover region's
# nodes (image pulls etc.). Mirrors the main stack's per-region pattern.
resource "google_compute_router" "failover" {
  name    = "${var.failover_cluster_name}-router"
  region  = var.failover_region
  network = data.google_compute_network.vpc.id
}

resource "google_compute_router_nat" "failover" {
  name                               = "${var.failover_cluster_name}-nat"
  router                             = google_compute_router.failover.name
  region                             = var.failover_region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
