# Three AWS providers — one per region. Provider aliasing is the standard pattern
# for multi-region Terraform; for_each cannot be applied to providers.

provider "aws" {
  alias  = "east"
  region = var.clusters["east"].region

  default_tags {
    tags = local.common_tags
  }
}

provider "aws" {
  alias  = "west"
  region = var.clusters["west"].region

  default_tags {
    tags = local.common_tags
  }
}

provider "aws" {
  alias  = "eu"
  region = var.clusters["eu"].region

  default_tags {
    tags = local.common_tags
  }
}

data "aws_caller_identity" "current" {
  provider = aws.east
}

# Kubernetes + Helm providers per cluster — exec auth via `aws eks get-token`.
# The cluster must exist at apply time; on first run, Terraform applies EKS
# before the kubernetes/helm resources, so this works without a multi-stage apply.

provider "kubernetes" {
  alias                  = "east"
  host                   = module.eks_east.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_east.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks_east.cluster_name, "--region", local.region_east]
  }
}

provider "kubernetes" {
  alias                  = "west"
  host                   = module.eks_west.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_west.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks_west.cluster_name, "--region", local.region_west]
  }
}

provider "kubernetes" {
  alias                  = "eu"
  host                   = module.eks_eu.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_eu.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks_eu.cluster_name, "--region", local.region_eu]
  }
}

provider "helm" {
  alias = "east"
  kubernetes {
    host                   = module.eks_east.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_east.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks_east.cluster_name, "--region", local.region_east]
    }
  }
}

provider "helm" {
  alias = "west"
  kubernetes {
    host                   = module.eks_west.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_west.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks_west.cluster_name, "--region", local.region_west]
    }
  }
}

provider "helm" {
  alias = "eu"
  kubernetes {
    host                   = module.eks_eu.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_eu.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks_eu.cluster_name, "--region", local.region_eu]
    }
  }
}
