resource "kubernetes_namespace" "redpanda_failover" {
  metadata { name = "redpanda" }
  depends_on = [azurerm_kubernetes_cluster.failover]
}

resource "kubernetes_service" "peer_failover" {
  metadata {
    name      = "${var.failover_cluster_name}-multicluster-peer"
    namespace = kubernetes_namespace.redpanda_failover.metadata[0].name
    annotations = {
      "service.beta.kubernetes.io/azure-load-balancer-internal" = "true"
    }
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
  depends_on = [azurerm_role_assignment.aks_failover_subnet]
}

data "kubernetes_service" "peer_failover" {
  metadata {
    name      = kubernetes_service.peer_failover.metadata[0].name
    namespace = kubernetes_service.peer_failover.metadata[0].namespace
  }
}
