variable "project_name" {
  description = "Tag value used by the main stack — must match for resource lookups by tag/name."
  type        = string
  default     = "redpanda-stretch-validation"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version — match the main stack."
  type        = string
  default     = "1.34"
}

variable "vm_size" {
  description = "VM size for the failover AKS node pool."
  type        = string
  default     = "Standard_D4s_v5"
}

variable "node_count" {
  description = "Per-cluster node count for the failover cluster. Default 2 fits the typical 10 vCPU/region sandbox quota for the DSv5 family (2× Standard_D4s_v5 = 8 vCPU, leaving headroom for upgrade surge nodes)."
  type        = number
  default     = 2
}

variable "node_disk_size_gb" {
  description = "OS disk size for each failover node (GiB)."
  type        = number
  default     = 50
}

# Failover-specific knobs. Defaults pick `eastus2` (~5 ms RTT to eastus,
# distinct from the main stack's eastus / westus2 / centralus). CIDRs do
# not overlap the main stack defaults (10.{10,20,30}.0.0/16 etc.).
variable "failover_region" {
  description = "Azure region for the failover cluster. Must be distinct from the three regions in the main stack's `clusters` map."
  type        = string
  default     = "eastus2"
}

variable "failover_cluster_name" {
  description = "Name of the failover AKS cluster (also the kubectl context alias after rename)."
  type        = string
  default     = "rp-failover"
}

variable "failover_vnet_cidr" {
  description = "VNet CIDR for the failover region."
  type        = string
  default     = "10.40.0.0/16"
}

variable "failover_subnet_cidr" {
  description = "Node subnet CIDR for the failover cluster."
  type        = string
  default     = "10.40.0.0/20"
}

variable "failover_pod_cidr" {
  description = "Pod CIDR for the failover AKS cluster (Azure CNI overlay)."
  type        = string
  default     = "10.140.0.0/16"
}

variable "failover_service_cidr" {
  description = "Service CIDR for the failover AKS cluster."
  type        = string
  default     = "10.141.0.0/20"
}

variable "failover_dns_service_ip" {
  description = "DNS service IP for the failover AKS cluster — must be inside failover_service_cidr."
  type        = string
  default     = "10.141.0.10"
}

# Existing-cluster identifiers — used to look up the main stack's resource
# groups, VNets, and NSGs. Match the defaults of the main stack's `clusters`
# map; override here if you customized it.
variable "existing_clusters" {
  description = "Existing region + cluster name + VNet CIDR for the three clusters provisioned by the main stack."
  type = map(object({
    region    = string
    name      = string
    vnet_cidr = string
  }))
  default = {
    east = { region = "eastus",     name = "rp-east", vnet_cidr = "10.10.0.0/16" }
    west = { region = "westus2",    name = "rp-west", vnet_cidr = "10.20.0.0/16" }
    eu   = { region = "westeurope", name = "rp-eu",   vnet_cidr = "10.30.0.0/16" }
  }
}

variable "cross_cluster_ports" {
  description = "TCP ports allowed between the failover VNet CIDR and the existing VNet CIDRs."
  type        = list(number)
  default     = [9443, 33145, 9093, 8082, 9644]
}
