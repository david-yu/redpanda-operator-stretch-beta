variable "project_name" {
  description = "Tag value for cost allocation / cleanup."
  type        = string
  default     = "redpanda-stretch-validation"
}

variable "owner" {
  description = "Tag value identifying the owner."
  type        = string
  default     = "redpanda-operator-stretch-beta"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.31"
}

variable "node_instance_type" {
  description = "EC2 instance type for the managed node group."
  type        = string
  default     = "m5.xlarge"
}

variable "node_count" {
  description = "Desired/min/max nodes per cluster (single nodegroup)."
  type        = number
  default     = 3
}

variable "node_volume_size_gb" {
  description = "Root EBS volume size for each node (GiB)."
  type        = number
  default     = 50
}

# Per-cluster knobs. Keys must be exactly: east, west, eu.
# CIDRs must not overlap (TGW peering requires distinct CIDRs).
variable "clusters" {
  description = "Per-cluster region + name + VPC CIDR."
  type = map(object({
    region   = string
    name     = string
    vpc_cidr = string
  }))
  default = {
    east = {
      region   = "us-east-1"
      name     = "rp-east"
      vpc_cidr = "10.10.0.0/16"
    }
    west = {
      region   = "us-west-2"
      name     = "rp-west"
      vpc_cidr = "10.20.0.0/16"
    }
    eu = {
      region   = "eu-west-1"
      name     = "rp-eu"
      vpc_cidr = "10.30.0.0/16"
    }
  }
}

# Ports that must be reachable across cluster CIDRs:
#   9443  — operator raft (peer-to-peer mTLS)
#   33145 — broker RPC (broker-to-broker)
#   9093  — Kafka client
#   8082  — Pandaproxy (HTTP REST)
#   9644  — Admin API
variable "cross_cluster_ports" {
  description = "TCP ports allowed between cluster VPC CIDRs."
  type        = list(number)
  default     = [9443, 33145, 9093, 8082, 9644]
}

# AWS Load Balancer Controller chart version.
variable "lbc_chart_version" {
  description = "Chart version for aws-load-balancer-controller."
  type        = string
  default     = "1.13.0"
}
