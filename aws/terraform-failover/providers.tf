# Four AWS providers — three aliased at the existing regions so we can
# create peering accepters and SG ingress rules in those regions, plus
# one for the new failover region. The main stack's AWS providers stay
# untouched — this stack reads existing infra via data sources only.

provider "aws" {
  alias  = "east"
  region = var.existing_clusters["east"].region
  default_tags { tags = local.common_tags }
}

provider "aws" {
  alias  = "west"
  region = var.existing_clusters["west"].region
  default_tags { tags = local.common_tags }
}

provider "aws" {
  alias  = "eu"
  region = var.existing_clusters["eu"].region
  default_tags { tags = local.common_tags }
}

provider "aws" {
  alias  = "failover"
  region = var.failover_region
  default_tags { tags = local.common_tags }
}

data "aws_caller_identity" "current" {
  provider = aws.failover
}

# Kubernetes + Helm providers for the failover cluster only — exec auth via
# `aws eks get-token`.
provider "kubernetes" {
  host                   = module.eks_failover.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_failover.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks_failover.cluster_name, "--region", var.failover_region]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks_failover.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_failover.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks_failover.cluster_name, "--region", var.failover_region]
    }
  }
}
