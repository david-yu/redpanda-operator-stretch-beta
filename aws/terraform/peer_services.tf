# Pre-create the per-cluster peer LB Service so AWS provisions an internal NLB
# (instead of the default Classic ELB internet-facing — see troubleshooting #3).
# `rpk k8s multicluster bootstrap --loadbalancer` reuses these via CreateOrUpdate
# and bakes the assigned hostname into TLS SANs.
#
# Service naming follows the bootstrap convention: <cluster.Name>-multicluster-peer.
# Selectors match the helm-installed operator pods (chart selector labels with
# release name == cluster context name, see step 6 of the root README).

locals {
  peer_svc_annotations = {
    "service.beta.kubernetes.io/aws-load-balancer-type"                              = "external"
    "service.beta.kubernetes.io/aws-load-balancer-scheme"                            = "internal"
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"                   = "ip"
    "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled" = "true"
  }
}

resource "kubernetes_namespace" "redpanda_east" {
  provider = kubernetes.east
  metadata { name = "redpanda" }
}

resource "kubernetes_namespace" "redpanda_west" {
  provider = kubernetes.west
  metadata { name = "redpanda" }
}

resource "kubernetes_namespace" "redpanda_eu" {
  provider = kubernetes.eu
  metadata { name = "redpanda" }
}

resource "kubernetes_service" "peer_east" {
  provider = kubernetes.east
  metadata {
    name        = "${local.cluster_name_east}-multicluster-peer"
    namespace   = kubernetes_namespace.redpanda_east.metadata[0].name
    annotations = local.peer_svc_annotations
  }
  spec {
    type = "LoadBalancer"
    selector = {
      "app.kubernetes.io/name"     = "operator"
      "app.kubernetes.io/instance" = local.cluster_name_east
    }
    port {
      name        = "raft"
      port        = 9443
      target_port = 9443
      protocol    = "TCP"
    }
    publish_not_ready_addresses = true
  }
  # Also depend on module.eks_east so destroy keeps the nodegroup alive until
  # the peer Service finishes draining; otherwise the AWS LB Controller can't
  # run to remove its finalizer and Terraform hangs on the Service deletion.
  depends_on = [helm_release.lbc_east, module.eks_east]
}

resource "kubernetes_service" "peer_west" {
  provider = kubernetes.west
  metadata {
    name        = "${local.cluster_name_west}-multicluster-peer"
    namespace   = kubernetes_namespace.redpanda_west.metadata[0].name
    annotations = local.peer_svc_annotations
  }
  spec {
    type = "LoadBalancer"
    selector = {
      "app.kubernetes.io/name"     = "operator"
      "app.kubernetes.io/instance" = local.cluster_name_west
    }
    port {
      name        = "raft"
      port        = 9443
      target_port = 9443
      protocol    = "TCP"
    }
    publish_not_ready_addresses = true
  }
  depends_on = [helm_release.lbc_west, module.eks_west]
}

resource "kubernetes_service" "peer_eu" {
  provider = kubernetes.eu
  metadata {
    name        = "${local.cluster_name_eu}-multicluster-peer"
    namespace   = kubernetes_namespace.redpanda_eu.metadata[0].name
    annotations = local.peer_svc_annotations
  }
  spec {
    type = "LoadBalancer"
    selector = {
      "app.kubernetes.io/name"     = "operator"
      "app.kubernetes.io/instance" = local.cluster_name_eu
    }
    port {
      name        = "raft"
      port        = 9443
      target_port = 9443
      protocol    = "TCP"
    }
    publish_not_ready_addresses = true
  }
  depends_on = [helm_release.lbc_eu, module.eks_eu]
}

# Wait for each NLB hostname to materialize so outputs.tf can surface it.
data "kubernetes_service" "peer_east" {
  provider = kubernetes.east
  metadata {
    name      = kubernetes_service.peer_east.metadata[0].name
    namespace = kubernetes_service.peer_east.metadata[0].namespace
  }
}

data "kubernetes_service" "peer_west" {
  provider = kubernetes.west
  metadata {
    name      = kubernetes_service.peer_west.metadata[0].name
    namespace = kubernetes_service.peer_west.metadata[0].namespace
  }
}

data "kubernetes_service" "peer_eu" {
  provider = kubernetes.eu
  metadata {
    name      = kubernetes_service.peer_eu.metadata[0].name
    namespace = kubernetes_service.peer_eu.metadata[0].namespace
  }
}
