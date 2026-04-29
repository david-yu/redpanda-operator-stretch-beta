locals {
  common_labels = {
    project    = var.project_name
    managed_by = "terraform"
  }

  region_east = var.clusters["east"].region
  region_west = var.clusters["west"].region
  region_eu   = var.clusters["eu"].region

  cluster_name_east = var.clusters["east"].name
  cluster_name_west = var.clusters["west"].name
  cluster_name_eu   = var.clusters["eu"].name

  # All pod CIDRs used by cross-cluster firewall sources.
  all_pod_cidrs = [for k, v in var.clusters : v.pods_cidr]
}
