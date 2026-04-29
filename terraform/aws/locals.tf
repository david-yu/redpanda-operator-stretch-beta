locals {
  common_tags = {
    Project   = var.project_name
    Owner     = var.owner
    ManagedBy = "terraform"
  }

  # Pre-derived per-cluster lookups so resources can reference by key.
  region_east = var.clusters["east"].region
  region_west = var.clusters["west"].region
  region_eu   = var.clusters["eu"].region

  cluster_name_east = var.clusters["east"].name
  cluster_name_west = var.clusters["west"].name
  cluster_name_eu   = var.clusters["eu"].name

  vpc_cidr_east = var.clusters["east"].vpc_cidr
  vpc_cidr_west = var.clusters["west"].vpc_cidr
  vpc_cidr_eu   = var.clusters["eu"].vpc_cidr
}
