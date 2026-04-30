# Terraform — GCP/GKE failover region (Demo B step 3)

Adds a **fourth** GKE cluster in a separate region (`us-central1` by default) on top of the main `gcp/terraform/` stack. Used by [Demo B](../../README.md#demo-b-regional-failure--temporary-failover-region-capacity-injection) to inject capacity when a primary region goes down: with RF=5 across 5 brokers, losing 2 of them blocks re-replication until 5 reachable brokers are back.

This stack is **independent** — it does not modify the main stack's terraform state. It uses a `data` source to look up the existing global VPC by name (`<project_name>-vpc`), creates a new subnet in the failover region, attaches a 4th GKE cluster, and adds an additive firewall rule that includes the failover pod CIDR alongside the main stack's three pod CIDRs. The main stack stays untouched, so you can apply / destroy this stack at any time without affecting the running 3-region cluster.

## Prerequisites

- The main `gcp/terraform/` stack already applied successfully (the failover stack looks up its VPC by name)
- `gcloud` authenticated, `gke-gcloud-auth-plugin` installed, the Compute + Kubernetes Engine APIs enabled in the same project — same as the main stack

## Apply

```bash
cd gcp/terraform-failover
terraform init
terraform apply -var project_id=<your-project-id>
```

First apply takes ~10–12 min (one regional GKE cluster).

## Outputs

```bash
terraform output -raw failover_kubectl_setup_command | bash    # registers context: rp-failover
terraform output failover_peer_lb_address                       # internal LB IP for multicluster.peers
terraform output -raw failover_gke_endpoint                     # for multicluster.apiServerExternalAddress
```

After this you continue with [Demo B step 4](../../README.md#demo-b-regional-failure--temporary-failover-region-capacity-injection) to bootstrap, install the operator, and apply the failover NodePool.

## Variables

| Var | Default | Notes |
|---|---|---|
| `project_id` | (required) | Must match the project where `gcp/terraform/` ran |
| `project_name` | `redpanda-stretch-validation` | Must match the main stack so we can find the VPC |
| `failover_region` | `us-central1` | Picked for low RTT (~35 ms) to the main stack's `us-east1`. |
| `failover_cluster_name` | `rp-failover` | Also the kubectl context alias after rename |
| `failover_subnet_cidr` | `10.40.0.0/20` | Must not overlap main stack's `10.{10,20,30}.0.0/20` |
| `failover_pods_cidr` | `10.140.0.0/16` | Must not overlap main stack's `10.{110,120,130}.0.0/16` |
| `failover_services_cidr` | `10.141.0.0/20` | Must not overlap main stack's `10.{111,121,131}.0.0/20` |
| `existing_pod_cidrs` | `["10.110.0.0/16", "10.120.0.0/16", "10.130.0.0/16"]` | Override if you customized the main stack's `clusters` map |
| `kubernetes_version` | `RAPID` | Match the main stack |
| `machine_type` | `n2-standard-4` | |
| `node_count` | `3` | Per-zone count for the regional pool (so 9 nodes total in failover) |
| `cross_cluster_ports` | `[9443, 33145, 9093, 8082, 9644]` | Match the main stack |

## Destroy

```bash
terraform destroy -var project_id=<your-project-id>
```

Destroys the failover GKE cluster, subnet, router/NAT, peer LB Service, and the additive firewall rule. The main stack is unaffected.

## Notes

- The failover cluster joins the same global VPC, so cross-region pod IP traffic to/from rp-east, rp-west, rp-eu works out of the box.
- The internal LB health-check firewall rule from the main stack already covers the failover region (it has no `destination_ranges`, so it applies to any backend in the VPC).
- After `terraform destroy`, remember to clean up the `rp-failover` kubectl context (`kubectl config delete-context rp-failover` plus the underlying cluster + user records — see step 4 in the root README's [Tear down](../../README.md#tear-down)).
