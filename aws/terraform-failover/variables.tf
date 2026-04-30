variable "project_name" {
  description = "Tag value used by the main stack — must match so we can look up existing TGWs/VPCs/SGs by tag."
  type        = string
  default     = "redpanda-stretch-validation"
}

variable "owner" {
  description = "Tag value identifying the owner — match the main stack."
  type        = string
  default     = "redpanda-operator-stretch-beta"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version — match the main stack."
  type        = string
  default     = "1.34"
}

variable "node_instance_type" {
  description = "EC2 instance type for the failover node group."
  type        = string
  default     = "m5.xlarge"
}

variable "node_count" {
  description = "Desired/min/max nodes for the failover cluster."
  type        = number
  default     = 3
}

variable "node_volume_size_gb" {
  description = "Root EBS volume size for each failover node (GiB)."
  type        = number
  default     = 50
}

# Failover-specific knobs. Defaults pick a 4th US region (us-east-2) with low
# RTT to the main stack's us-east-1, and a CIDR that doesn't overlap the
# main stack's defaults (10.{10,20,30}.0.0/16).
variable "failover_region" {
  description = "AWS region for the failover cluster."
  type        = string
  default     = "us-east-2"
}

variable "failover_cluster_name" {
  description = "Name of the failover EKS cluster (also the kubectl context alias after rename)."
  type        = string
  default     = "rp-failover"
}

variable "failover_vpc_cidr" {
  description = "VPC CIDR for the failover region. Must not overlap the main stack's VPC CIDRs."
  type        = string
  default     = "10.40.0.0/16"
}

variable "failover_tgw_asn" {
  description = "Amazon-side ASN for the failover TGW. Must be unique across the four TGWs in the mesh."
  type        = number
  default     = 64903
}

# Existing-cluster identifiers — used by data sources to look up the main
# stack's VPCs, TGWs, and node SGs. Defaults match the main stack's defaults;
# override if you customized the `clusters` map there.
variable "existing_clusters" {
  description = "Existing region + cluster name + VPC CIDR for the three clusters provisioned by the main stack."
  type = map(object({
    region   = string
    name     = string
    vpc_cidr = string
  }))
  default = {
    east = { region = "us-east-1", name = "rp-east", vpc_cidr = "10.10.0.0/16" }
    west = { region = "us-west-2", name = "rp-west", vpc_cidr = "10.20.0.0/16" }
    eu   = { region = "eu-west-1", name = "rp-eu",   vpc_cidr = "10.30.0.0/16" }
  }
}

variable "cross_cluster_ports" {
  description = "TCP ports allowed between the failover VPC CIDR and the existing VPC CIDRs."
  type        = list(number)
  default     = [9443, 33145, 9093, 8082, 9644]
}
