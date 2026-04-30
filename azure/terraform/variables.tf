variable "project_name" {
  description = "Tag value used in resource group and resource names."
  type        = string
  default     = "redpanda-stretch-validation"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version. Must be a currently-supported (non-LTS-only) GA version — `az aks get-versions --location <region>` lists what's available. AKS rolls 1.31 / 1.30 / older to LTS-only periodically; bump this when that happens."
  type        = string
  default     = "1.34"
}

variable "vm_size" {
  description = "VM size for AKS node pools."
  type        = string
  default     = "Standard_D4s_v5"
}

variable "node_count" {
  description = "Per-cluster node count. With the default Standard_D4s_v5 (4 vCPU each) this consumes 8 vCPUs/region — bump up only if your subscription's regional vCPU quota for the DSv5 family allows it (default sandbox quota is 10/region)."
  type        = number
  default     = 2
}

variable "node_disk_size_gb" {
  description = "OS disk size for each node (GiB)."
  type        = number
  default     = 50
}

# Per-cluster knobs. Keys must be exactly: east, west, eu.
# Each cluster has its own VNet (Azure VNets are regional). VNet peering is
# established full-mesh. Subnet/pod/service CIDRs must not overlap.
variable "clusters" {
  description = "Per-cluster region + name + VNet CIDR + node subnet + pod CIDR + service CIDR."
  type = map(object({
    region         = string
    name           = string
    vnet_cidr      = string
    subnet_cidr    = string
    pod_cidr       = string
    service_cidr   = string
    dns_service_ip = string
  }))
  default = {
    east = {
      region         = "eastus"
      name           = "rp-east"
      vnet_cidr      = "10.10.0.0/16"
      subnet_cidr    = "10.10.0.0/20"
      pod_cidr       = "10.110.0.0/16"
      service_cidr   = "10.111.0.0/20"
      dns_service_ip = "10.111.0.10"
    }
    west = {
      region         = "westus2"
      name           = "rp-west"
      vnet_cidr      = "10.20.0.0/16"
      subnet_cidr    = "10.20.0.0/20"
      pod_cidr       = "10.120.0.0/16"
      service_cidr   = "10.121.0.0/20"
      dns_service_ip = "10.121.0.10"
    }
    eu = {
      region         = "centralus"
      name           = "rp-eu"
      vnet_cidr      = "10.30.0.0/16"
      subnet_cidr    = "10.30.0.0/20"
      pod_cidr       = "10.130.0.0/16"
      service_cidr   = "10.131.0.0/20"
      dns_service_ip = "10.131.0.10"
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
  description = "TCP ports allowed between cluster VNet CIDRs."
  type        = list(number)
  default     = [9443, 33145, 9093, 8082, 9644]
}
