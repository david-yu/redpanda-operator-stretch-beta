# Terraform — GCP/GKE (steps 1–4)

Provisions everything the stretch cluster needs **before** `rpk k8s multicluster bootstrap`:

| Step | Resource |
|---|---|
| 1 | Single global VPC + 3 regional subnets + Cloud Router/NAT per region for outbound |
| 1 | 3× regional GKE clusters with Workload Identity, VPC-native networking |
| 2 | Cross-region firewall rules for ports 9443/33145/9093/8082/9644 across pod CIDRs |
| 3 | *(no separate LB controller needed — GKE has built-in Internal Network LB support)* |
| 4 | One `redpanda` namespace + one `<cluster>-multicluster-peer` Internal LB Service per cluster (port 9443, global access enabled) |

GCP makes this simpler than AWS in two ways:
- **VPCs are global** — one VPC with regional subnets, no peering required for cross-region pod-to-pod traffic.
- **Internal Passthrough Network LB is native** — annotations on the Service are all you need; no separate AWS-LBC-style controller install.

## Prerequisites

- Terraform ≥ 1.6
- `gcloud` CLI authenticated (`gcloud auth application-default login`)
- `gke-gcloud-auth-plugin` installed (Terraform's kubernetes provider uses it via exec)
  ```bash
  gcloud components install gke-gcloud-auth-plugin
  ```
- `kubectl`, `helm`, `aws` (no — but rpk + plugin) on PATH for steps 5+
- A GCP project with these APIs enabled:
  ```bash
  gcloud services enable container.googleapis.com compute.googleapis.com --project <PROJECT_ID>
  ```

## Apply

```bash
cd terraform/gcp
terraform init
terraform apply -var project_id=<your-project-id>
```

First apply takes ~15–20 minutes (regional GKE clusters take ~10 min each, parallelized).

## Outputs

```bash
terraform output -raw kubectl_setup_commands | bash    # registers contexts: rp-east rp-west rp-eu
terraform output peer_lb_addresses                     # paste into multicluster.peers
terraform output gke_endpoints                         # paste into multicluster.apiServerExternalAddress
```

After that you have everything you need for steps 5+ in the root README.

## Variables

| Var | Default | Notes |
|---|---|---|
| `project_id` | (required) | GCP project where clusters are created |
| `clusters` | east/west/eu in us-east1/us-west1/europe-west1 with non-overlapping subnets/pods/services CIDRs | All under one global VPC |
| `kubernetes_version` | `RAPID` | GKE release channel |
| `machine_type` | `n2-standard-4` | |
| `node_count` | 3 | Per regional cluster |
| `cross_cluster_ports` | `[9443, 33145, 9093, 8082, 9644]` | |

## Destroy

```bash
terraform destroy -var project_id=<your-project-id>
```

Order is automatic via the dependency graph: peer Services and their LBs first, then GKE clusters, then NAT/Router/firewall, then VPC.

## Notes

- The control plane endpoint is public by default for Terraform/kubectl access. To lock down, set `private_cluster_config` on `google_container_cluster` and add `master_authorized_networks_config` for your operator host.
- Workload Identity is enabled cluster-wide. The Redpanda operator doesn't currently call any GCP APIs, so no GSA mapping is required for it — the feature is on simply because best practice.
