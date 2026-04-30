locals {
  common_tags = {
    project    = var.project_name
    managed_by = "terraform"
    role       = "failover"
  }

  existing_vnet_cidrs = [for k, v in var.existing_clusters : v.vnet_cidr]
  all_vnet_cidrs      = concat(local.existing_vnet_cidrs, [var.failover_vnet_cidr])
}
