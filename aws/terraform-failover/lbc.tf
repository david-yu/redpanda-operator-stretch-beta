# AWS Load Balancer Controller for the failover cluster.
# Mirrors the main stack's lbc.tf so the peer Service in peer_services.tf
# can provision its internal NLB. Without LBC the kubernetes_service
# resource hangs forever waiting for `.status.loadBalancer.ingress`.

module "lbc_role_failover" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.48"
  providers = { aws = aws.failover }

  role_name                              = "${var.failover_cluster_name}-aws-lbc"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks_failover.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "kubernetes_service_account" "lbc_failover" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = module.lbc_role_failover.iam_role_arn
    }
  }
}

resource "helm_release" "lbc_failover" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = var.lbc_chart_version

  set {
    name  = "clusterName"
    value = var.failover_cluster_name
  }
  set {
    name  = "serviceAccount.create"
    value = "false"
  }
  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.lbc_failover.metadata[0].name
  }
}
