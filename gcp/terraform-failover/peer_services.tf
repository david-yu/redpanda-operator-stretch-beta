# Pre-create the redpanda namespace + peer LB Service in the failover
# cluster so `rpk k8s multicluster bootstrap` can pick up the existing
# Service via CreateOrUpdate, preserving the GKE-specific annotations
# (Internal Passthrough Network LB with global access enabled).

locals {
  peer_svc_annotations = {
    "networking.gke.io/load-balancer-type"                         = "Internal"
    "networking.gke.io/internal-load-balancer-allow-global-access" = "true"
  }
}

resource "kubernetes_namespace" "redpanda_failover" {
  metadata { name = "redpanda" }
  depends_on = [google_container_node_pool.failover]
}

resource "kubernetes_service" "peer_failover" {
  metadata {
    name        = "${var.failover_cluster_name}-multicluster-peer"
    namespace   = kubernetes_namespace.redpanda_failover.metadata[0].name
    annotations = local.peer_svc_annotations
  }
  spec {
    type = "LoadBalancer"
    selector = {
      "app.kubernetes.io/name"     = "operator"
      "app.kubernetes.io/instance" = var.failover_cluster_name
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

data "kubernetes_service" "peer_failover" {
  metadata {
    name      = kubernetes_service.peer_failover.metadata[0].name
    namespace = kubernetes_service.peer_failover.metadata[0].namespace
  }
}
