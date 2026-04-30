# AWS Load Balancer Controller per cluster: IRSA role + helm release.
# The IRSA module pulls the canonical IAM policy from the LBC project and
# attaches it to a dedicated role assumed by the controller's service account.

module "lbc_role_east" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.48"
  providers = { aws = aws.east }

  role_name                              = "${local.cluster_name_east}-aws-lbc"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks_east.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

module "lbc_role_west" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.48"
  providers = { aws = aws.west }

  role_name                              = "${local.cluster_name_west}-aws-lbc"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks_west.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

module "lbc_role_eu" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.48"
  providers = { aws = aws.eu }

  role_name                              = "${local.cluster_name_eu}-aws-lbc"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks_eu.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

# Service accounts — created with IRSA annotation pointing at the LBC role.
resource "kubernetes_service_account" "lbc_east" {
  provider = kubernetes.east
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = module.lbc_role_east.iam_role_arn
    }
  }
}

resource "kubernetes_service_account" "lbc_west" {
  provider = kubernetes.west
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = module.lbc_role_west.iam_role_arn
    }
  }
}

resource "kubernetes_service_account" "lbc_eu" {
  provider = kubernetes.eu
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = module.lbc_role_eu.iam_role_arn
    }
  }
}

# Helm releases.
resource "helm_release" "lbc_east" {
  provider   = helm.east
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = var.lbc_chart_version

  set {
    name  = "clusterName"
    value = local.cluster_name_east
  }
  set {
    name  = "serviceAccount.create"
    value = "false"
  }
  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.lbc_east.metadata[0].name
  }
}

resource "helm_release" "lbc_west" {
  provider   = helm.west
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = var.lbc_chart_version

  set {
    name  = "clusterName"
    value = local.cluster_name_west
  }
  set {
    name  = "serviceAccount.create"
    value = "false"
  }
  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.lbc_west.metadata[0].name
  }
}

resource "helm_release" "lbc_eu" {
  provider   = helm.eu
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = var.lbc_chart_version

  set {
    name  = "clusterName"
    value = local.cluster_name_eu
  }
  set {
    name  = "serviceAccount.create"
    value = "false"
  }
  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.lbc_eu.metadata[0].name
  }
}
