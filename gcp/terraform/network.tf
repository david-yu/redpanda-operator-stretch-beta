# GCP VPCs are global — one VPC with three regional subnets is enough for
# cross-region pod-to-pod traffic. No peering or interconnect required.

resource "google_compute_network" "vpc" {
  name                    = "${var.project_name}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"
}

# One subnet per region for cluster nodes, plus secondary ranges for the
# pods and Services (VPC-native cluster requirement).
resource "google_compute_subnetwork" "east" {
  name          = "${local.cluster_name_east}-subnet"
  region        = local.region_east
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.clusters["east"].subnet_cidr

  secondary_ip_range {
    range_name    = "${local.cluster_name_east}-pods"
    ip_cidr_range = var.clusters["east"].pods_cidr
  }
  secondary_ip_range {
    range_name    = "${local.cluster_name_east}-services"
    ip_cidr_range = var.clusters["east"].services_cidr
  }

  private_ip_google_access = true
}

resource "google_compute_subnetwork" "west" {
  name          = "${local.cluster_name_west}-subnet"
  region        = local.region_west
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.clusters["west"].subnet_cidr

  secondary_ip_range {
    range_name    = "${local.cluster_name_west}-pods"
    ip_cidr_range = var.clusters["west"].pods_cidr
  }
  secondary_ip_range {
    range_name    = "${local.cluster_name_west}-services"
    ip_cidr_range = var.clusters["west"].services_cidr
  }

  private_ip_google_access = true
}

resource "google_compute_subnetwork" "eu" {
  name          = "${local.cluster_name_eu}-subnet"
  region        = local.region_eu
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.clusters["eu"].subnet_cidr

  secondary_ip_range {
    range_name    = "${local.cluster_name_eu}-pods"
    ip_cidr_range = var.clusters["eu"].pods_cidr
  }
  secondary_ip_range {
    range_name    = "${local.cluster_name_eu}-services"
    ip_cidr_range = var.clusters["eu"].services_cidr
  }

  private_ip_google_access = true
}

# Cloud Router + Cloud NAT per region — private nodes need outbound internet
# for image pulls.
resource "google_compute_router" "east" {
  name    = "${local.cluster_name_east}-router"
  region  = local.region_east
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "east" {
  name                               = "${local.cluster_name_east}-nat"
  router                             = google_compute_router.east.name
  region                             = local.region_east
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_compute_router" "west" {
  name    = "${local.cluster_name_west}-router"
  region  = local.region_west
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "west" {
  name                               = "${local.cluster_name_west}-nat"
  router                             = google_compute_router.west.name
  region                             = local.region_west
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_compute_router" "eu" {
  name    = "${local.cluster_name_eu}-router"
  region  = local.region_eu
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "eu" {
  name                               = "${local.cluster_name_eu}-nat"
  router                             = google_compute_router.eu.name
  region                             = local.region_eu
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
