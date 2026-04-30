variable "project_id" {
  description = "GCP project ID where the GKE clusters will be created."
  type        = string
}

variable "project_name" {
  description = "Tag value for cost allocation / cleanup."
  type        = string
  default     = "redpanda-stretch-validation"
}

variable "kubernetes_version" {
  description = "GKE release channel — RAPID tracks the latest GA minor (~1.35.x at time of writing), REGULAR is ~1 minor behind, STABLE is ~2-3 minor behind. The channel auto-picks and auto-upgrades the patch version, so this terraform doesn't pin a specific 1.x.y."
  type        = string
  default     = "RAPID"
  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.kubernetes_version)
    error_message = "Pick one of RAPID, REGULAR, STABLE."
  }
}

variable "machine_type" {
  description = "GCE machine type for the default node pool."
  type        = string
  default     = "n2-standard-4"
}

variable "node_count" {
  description = "Per-zone node count for the regional GKE node pool. Regional clusters distribute this number to EACH of the region's zones (typically 3), so node_count=1 → 3 nodes/cluster, node_count=2 → 6 nodes/cluster, etc. The default 1 keeps zonal HA (1 node in each zone) while matching the per-cluster broker workload (2 broker pods + operator + cert-manager) — the previous default of 3 ran 9 nodes/cluster (27 across the stretch cluster) which is significantly over-provisioned for this validation."
  type        = number
  default     = 1
}

variable "node_disk_size_gb" {
  description = "Boot disk size for each node (GiB)."
  type        = number
  default     = 50
}

# Per-cluster knobs. Keys must be exactly: east, west, eu.
# Subnets share a single global VPC — GCP VPCs are global, so cross-region
# pod traffic flows natively without peering. Subnet CIDRs must not overlap.
variable "clusters" {
  description = "Per-cluster region + name + subnet CIDR + pod/service ranges."
  type = map(object({
    region        = string
    name          = string
    subnet_cidr   = string
    pods_cidr     = string
    services_cidr = string
  }))
  default = {
    east = {
      region        = "us-east1"
      name          = "rp-east"
      subnet_cidr   = "10.10.0.0/20"
      pods_cidr     = "10.110.0.0/16"
      services_cidr = "10.111.0.0/20"
    }
    west = {
      region        = "us-west1"
      name          = "rp-west"
      subnet_cidr   = "10.20.0.0/20"
      pods_cidr     = "10.120.0.0/16"
      services_cidr = "10.121.0.0/20"
    }
    eu = {
      region        = "us-east4"
      name          = "rp-eu"
      subnet_cidr   = "10.30.0.0/20"
      pods_cidr     = "10.130.0.0/16"
      services_cidr = "10.131.0.0/20"
    }
  }
}

# Ports that must be reachable across cluster pod CIDRs:
#   9443  — operator raft (peer-to-peer mTLS)
#   33145 — broker RPC (broker-to-broker)
#   9093  — Kafka client
#   8082  — Pandaproxy (HTTP REST)
#   9644  — Admin API
variable "cross_cluster_ports" {
  description = "TCP ports allowed between cluster pod CIDRs."
  type        = list(number)
  default     = [9443, 33145, 9093, 8082, 9644]
}
