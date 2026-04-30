locals {
  common_tags = {
    Project   = var.project_name
    Owner     = var.owner
    ManagedBy = "terraform"
    Role      = "failover"
  }

  existing_vpc_cidrs = [for k, v in var.existing_clusters : v.vpc_cidr]

  # All VPC CIDRs (main 3 + failover) — used as source of failover SG ingress.
  all_vpc_cidrs = concat(local.existing_vpc_cidrs, [var.failover_vpc_cidr])
}
