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
  description = "GKE control plane release channel — let the channel pick the version."
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
  description = "Per-region node count (single regional node pool)."
  type        = number
  default     = 3
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
