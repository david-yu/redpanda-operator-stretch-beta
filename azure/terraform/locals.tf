locals {
  common_tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
  }

  region_east = var.clusters["east"].region
  region_west = var.clusters["west"].region
  region_eu   = var.clusters["eu"].region

  cluster_name_east = var.clusters["east"].name
  cluster_name_west = var.clusters["west"].name
  cluster_name_eu   = var.clusters["eu"].name

  # All VNet CIDRs used by NSG rules so pods in any cluster can reach pods
  # in any cluster on the cross-cluster ports.
  all_vnet_cidrs = [for k, v in var.clusters : v.vnet_cidr]
}
