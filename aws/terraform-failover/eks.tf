module "eks_failover" {
  source    = "terraform-aws-modules/eks/aws"
  version   = "~> 20.24"
  providers = { aws = aws.failover }

  cluster_name    = var.failover_cluster_name
  cluster_version = var.kubernetes_version

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  vpc_id     = module.vpc_failover.vpc_id
  subnet_ids = module.vpc_failover.private_subnets

  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    coredns            = {}
    kube-proxy         = {}
    vpc-cni            = {}
    aws-ebs-csi-driver = { service_account_role_arn = module.ebs_csi_role_failover.iam_role_arn }
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

module "ebs_csi_role_failover" {
  source    = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version   = "~> 5.48"
  providers = { aws = aws.failover }

  role_name             = "${var.failover_cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks_failover.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# Patch gp2 to be the default StorageClass — same reason as the main stack.
resource "kubernetes_annotations" "gp2_default_failover" {
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata { name = "gp2" }
  annotations = { "storageclass.kubernetes.io/is-default-class" = "true" }
  force       = true
  depends_on  = [module.eks_failover]
}
