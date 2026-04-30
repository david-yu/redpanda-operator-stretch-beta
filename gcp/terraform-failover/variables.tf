variable "project_id" {
  description = "GCP project ID — must match the project where the main stack ran."
  type        = string
}

variable "project_name" {
  description = "Tag value used by the main stack — must match so we can look up the existing VPC by name."
  type        = string
  default     = "redpanda-stretch-validation"
}

# Failover-specific knobs. Defaults pick a 4th US region with sub-50ms RTT to
# the main stack's us-east1 / us-west1 / us-east4 set, and CIDRs that don't
# overlap any of the main stack's defaults (10.{10,20,30}.x.x for subnets,
# 10.{110,120,130}.x.x for pods, 10.{111,121,131}.x.x for services).
variable "failover_region" {
  description = "GCP region for the failover cluster."
  type        = string
  default     = "us-central1"
}

variable "failover_cluster_name" {
  description = "Name of the failover GKE cluster (also the kubectl context alias the outputs will register)."
  type        = string
  default     = "rp-failover"
}

variable "failover_subnet_cidr" {
  description = "Subnet CIDR for the failover region. Must not overlap the main stack's subnet CIDRs."
  type        = string
  default     = "10.40.0.0/20"
}

variable "failover_pods_cidr" {
  description = "Pod CIDR (secondary range) for the failover cluster. Must not overlap the main stack's pod CIDRs."
  type        = string
  default     = "10.140.0.0/16"
}

variable "failover_services_cidr" {
  description = "Service CIDR (secondary range) for the failover cluster. Must not overlap the main stack's service CIDRs."
  type        = string
  default     = "10.141.0.0/20"
}

# Pod CIDRs from the main stack — the failover firewall rule needs both this
# list AND the failover_pods_cidr as source/destination so all four clusters
# can reach each other. Defaults match the main stack's defaults; override
# if you customized the `clusters` map there.
variable "existing_pod_cidrs" {
  description = "Pod CIDRs of the three existing clusters (rp-east, rp-west, rp-eu)."
  type        = list(string)
  default     = ["10.110.0.0/16", "10.120.0.0/16", "10.130.0.0/16"]
}

variable "kubernetes_version" {
  description = "GKE control plane release channel — match the main stack."
  type        = string
  default     = "RAPID"
  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.kubernetes_version)
    error_message = "Pick one of RAPID, REGULAR, STABLE."
  }
}

variable "machine_type" {
  description = "GCE machine type for the failover node pool."
  type        = string
  default     = "n2-standard-4"
}

variable "node_count" {
  description = "Per-zone node count for the regional failover node pool. Regional clusters distribute this to each zone, so default 1 → 3 nodes total (one per zone) — enough headroom for the 2 failover broker pods, operator, and cert-manager."
  type        = number
  default     = 1
}

variable "node_disk_size_gb" {
  description = "Boot disk size for each failover node (GiB)."
  type        = number
  default     = 50
}

variable "cross_cluster_ports" {
  description = "TCP ports allowed between the failover pod CIDR and the existing pod CIDRs. Match the main stack."
  type        = list(number)
  default     = [9443, 33145, 9093, 8082, 9644]
}
