# Additive firewall rule that includes the failover pod CIDR alongside the
# main stack's three pod CIDRs as both source and destination. The main
# stack's existing `<project>-cross-cluster` rule still covers the
# existing↔existing legs; this rule covers any leg involving failover.
# GCP firewall rules are additive, so the overlap is harmless.

resource "google_compute_firewall" "failover_cross_cluster_pod_to_pod" {
  name        = "${var.project_name}-failover-cross-cluster"
  network     = data.google_compute_network.vpc.name
  description = "Stretch cluster cross-region pod traffic involving the failover region (operator raft, broker RPC, Kafka, Pandaproxy, Admin)"

  direction          = "INGRESS"
  source_ranges      = local.all_pod_cidrs
  destination_ranges = local.all_pod_cidrs

  allow {
    protocol = "tcp"
    ports    = [for p in var.cross_cluster_ports : tostring(p)]
  }
}

# Note: the main stack's `<project>-lb-healthchecks` rule has no
# destination_ranges set, so it already covers any backend in the VPC —
# including failover region pods. No new health-check rule needed.
