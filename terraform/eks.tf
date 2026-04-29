# Three EKS clusters using the standard module. Each cluster has:
#   - control plane K8s ${var.kubernetes_version}
#   - one managed node group (m5.xlarge × 3 by default) in private subnets
#   - the four standard addons including the EBS CSI driver (for Redpanda PVCs)
#   - IRSA enabled for AWS LB Controller and EBS CSI driver
#   - public + private API endpoint access (private only is fine too if you
#     drop the public endpoint and run terraform from inside the VPC)

module "eks_east" {
  source    = "terraform-aws-modules/eks/aws"
  version   = "~> 20.24"
  providers = { aws = aws.east }

  cluster_name    = local.cluster_name_east
  cluster_version = var.kubernetes_version

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  vpc_id     = module.vpc_east.vpc_id
  subnet_ids = module.vpc_east.private_subnets

  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    coredns            = {}
    kube-proxy         = {}
    vpc-cni            = {}
    aws-ebs-csi-driver = { service_account_role_arn = module.ebs_csi_role_east.iam_role_arn }
  }

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = [var.node_instance_type]

      min_size     = var.node_count
      max_size     = var.node_count
      desired_size = var.node_count

      disk_size = var.node_volume_size_gb
    }
  }
}

module "eks_west" {
  source    = "terraform-aws-modules/eks/aws"
  version   = "~> 20.24"
  providers = { aws = aws.west }

  cluster_name    = local.cluster_name_west
  cluster_version = var.kubernetes_version

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  vpc_id     = module.vpc_west.vpc_id
  subnet_ids = module.vpc_west.private_subnets

  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    coredns            = {}
    kube-proxy         = {}
    vpc-cni            = {}
    aws-ebs-csi-driver = { service_account_role_arn = module.ebs_csi_role_west.iam_role_arn }
  }

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = [var.node_instance_type]

      min_size     = var.node_count
      max_size     = var.node_count
      desired_size = var.node_count

      disk_size = var.node_volume_size_gb
    }
  }
}

module "eks_eu" {
  source    = "terraform-aws-modules/eks/aws"
  version   = "~> 20.24"
  providers = { aws = aws.eu }

  cluster_name    = local.cluster_name_eu
  cluster_version = var.kubernetes_version

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  vpc_id     = module.vpc_eu.vpc_id
  subnet_ids = module.vpc_eu.private_subnets

  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    coredns            = {}
    kube-proxy         = {}
    vpc-cni            = {}
    aws-ebs-csi-driver = { service_account_role_arn = module.ebs_csi_role_eu.iam_role_arn }
  }

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = [var.node_instance_type]

      min_size     = var.node_count
      max_size     = var.node_count
      desired_size = var.node_count

      disk_size = var.node_volume_size_gb
    }
  }
}

# IRSA roles for the EBS CSI driver — needed for PV provisioning.
module "ebs_csi_role_east" {
  source    = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version   = "~> 5.48"
  providers = { aws = aws.east }

  role_name             = "${local.cluster_name_east}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks_east.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

module "ebs_csi_role_west" {
  source    = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version   = "~> 5.48"
  providers = { aws = aws.west }

  role_name             = "${local.cluster_name_west}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks_west.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

module "ebs_csi_role_eu" {
  source    = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version   = "~> 5.48"
  providers = { aws = aws.eu }

  role_name             = "${local.cluster_name_eu}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks_eu.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# Patch gp2 to be the default StorageClass on every cluster — newer EKS doesn't
# annotate gp2 default, and the chart's PVC has no explicit class, so PVCs
# would otherwise sit Pending forever. See troubleshooting #11.
resource "kubernetes_annotations" "gp2_default_east" {
  provider    = kubernetes.east
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata { name = "gp2" }
  annotations = { "storageclass.kubernetes.io/is-default-class" = "true" }
  force       = true
  depends_on  = [module.eks_east]
}

resource "kubernetes_annotations" "gp2_default_west" {
  provider    = kubernetes.west
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata { name = "gp2" }
  annotations = { "storageclass.kubernetes.io/is-default-class" = "true" }
  force       = true
  depends_on  = [module.eks_west]
}

resource "kubernetes_annotations" "gp2_default_eu" {
  provider    = kubernetes.eu
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata { name = "gp2" }
  annotations = { "storageclass.kubernetes.io/is-default-class" = "true" }
  force       = true
  depends_on  = [module.eks_eu]
}
