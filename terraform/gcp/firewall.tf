# GCP firewall rules — applied at the VPC level, scoped to source/destination
# CIDRs (no need for per-cluster SGs like AWS).
#
# Cross-cluster pod-to-pod traffic on the operator + broker ports. Sources
# are the THREE pod CIDRs (each cluster's pod range can reach pods in any
# cluster on these ports).

resource "google_compute_firewall" "cross_cluster_pod_to_pod" {
  name        = "${var.project_name}-cross-cluster"
  network     = google_compute_network.vpc.name
  description = "Stretch cluster cross-region pod traffic (operator raft, broker RPC, Kafka, Pandaproxy, Admin)"

  direction          = "INGRESS"
  source_ranges      = local.all_pod_cidrs
  destination_ranges = local.all_pod_cidrs

  allow {
    protocol = "tcp"
    ports    = [for p in var.cross_cluster_ports : tostring(p)]
  }
}

# Internal LB health checks come from these GCP-managed ranges. Required
# for the Internal Passthrough Network LB to mark backends healthy.
resource "google_compute_firewall" "lb_health_checks" {
  name        = "${var.project_name}-lb-healthchecks"
  network     = google_compute_network.vpc.name
  description = "Allow GCP LB health checks to reach backend pods"

  direction     = "INGRESS"
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22", "209.85.152.0/22", "209.85.204.0/22"]

  allow {
    protocol = "tcp"
    ports    = [for p in var.cross_cluster_ports : tostring(p)]
  }
}
