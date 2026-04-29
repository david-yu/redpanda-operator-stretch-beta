# GCP VPCs are global so a single google provider handles all regions.

provider "google" {
  project = var.project_id
}

# Kubernetes providers per cluster — exec auth via gcloud.
# Three aliases because the kubernetes provider doesn't accept for_each.

provider "kubernetes" {
  alias                  = "east"
  host                   = "https://${google_container_cluster.east.endpoint}"
  cluster_ca_certificate = base64decode(google_container_cluster.east.master_auth[0].cluster_ca_certificate)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "gke-gcloud-auth-plugin"
  }
}

provider "kubernetes" {
  alias                  = "west"
  host                   = "https://${google_container_cluster.west.endpoint}"
  cluster_ca_certificate = base64decode(google_container_cluster.west.master_auth[0].cluster_ca_certificate)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "gke-gcloud-auth-plugin"
  }
}

provider "kubernetes" {
  alias                  = "eu"
  host                   = "https://${google_container_cluster.eu.endpoint}"
  cluster_ca_certificate = base64decode(google_container_cluster.eu.master_auth[0].cluster_ca_certificate)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "gke-gcloud-auth-plugin"
  }
}
