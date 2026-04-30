# Pre-create the redpanda namespace + peer LB Service in the failover
# cluster so `rpk k8s multicluster bootstrap --loadbalancer` picks up the
# existing Service via CreateOrUpdate, preserving the AWS-LBC annotations
# that make it an internal NLB (instead of a vanilla internet-facing ELB).
#
# NOTE: this depends on the AWS Load Balancer Controller being installed
# on the failover cluster. The main stack installs LBC via Helm; we don't
# duplicate that here since adding it would require a separate Helm release
# in this stack. If the failover cluster doesn't have LBC, the Service
# stays Pending and bootstrap fails. Two options:
#   A) install LBC on rp-failover by hand: `helm install aws-load-balancer-controller ...`
#      using the same chart version as the main stack
#   B) re-use the main stack's `aws/terraform/lbc.tf` block and copy it here

resource "kubernetes_namespace" "redpanda_failover" {
  metadata { name = "redpanda" }
  depends_on = [module.eks_failover]
}

resource "kubernetes_service" "peer_failover" {
  metadata {
    name      = "${var.failover_cluster_name}-multicluster-peer"
    namespace = kubernetes_namespace.redpanda_failover.metadata[0].name
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
      "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
      "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internal"
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
}

data "kubernetes_service" "peer_failover" {
  metadata {
    name      = kubernetes_service.peer_failover.metadata[0].name
    namespace = kubernetes_service.peer_failover.metadata[0].namespace
  }
}
