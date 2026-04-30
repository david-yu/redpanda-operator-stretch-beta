# Pre-create the per-cluster peer LB Service so AKS provisions an Internal
# Standard Load Balancer. `rpk k8s multicluster bootstrap --loadbalancer`
# reuses these via CreateOrUpdate and bakes the assigned IP into TLS SANs.

locals {
  peer_svc_annotations = {
    "service.beta.kubernetes.io/azure-load-balancer-internal" = "true"
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
}

# Wait for each LB IP to materialize.
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
