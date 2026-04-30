locals {
  common_labels = {
    project    = var.project_name
    managed_by = "terraform"
    role       = "failover"
  }

  # All four pod CIDRs — used as source AND destination of the failover
  # cross-cluster firewall rule (overlaps with the main stack's existing
  # rule for the existing↔existing legs, but that's harmless since GCP
  # firewalls are additive).
  all_pod_cidrs = concat(var.existing_pod_cidrs, [var.failover_pods_cidr])
}
