provider "google" {
  project = var.project_id
}

# Single kubernetes provider for the failover cluster — exec auth via
# gcloud. The main stack's east/west/eu providers stay untouched (we never
# read or write to those clusters from this stack; bootstrap is run as a
# separate `rpk k8s multicluster bootstrap` step after `terraform apply`).
provider "kubernetes" {
  host                   = "https://${google_container_cluster.failover.endpoint}"
  cluster_ca_certificate = base64decode(google_container_cluster.failover.master_auth[0].cluster_ca_certificate)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "gke-gcloud-auth-plugin"
  }
}
