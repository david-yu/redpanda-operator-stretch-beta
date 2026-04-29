# Terraform — Azure/AKS (steps 1–4)

Provisions everything the stretch cluster needs **before** `rpk k8s multicluster bootstrap`:

| Step | Resource |
|---|---|
| 1 | 3× Resource Groups + 3× VNets (one per region) + node subnets |
| 1 | 3× AKS clusters with Azure CNI overlay, system-assigned managed identity |
| 2 | Full-mesh VNet peering (6 unidirectional peerings — Azure peerings are one-way) |
| 2 | NSGs per cluster with cross-cluster ingress rules for ports 9443/33145/9093/8082/9644 |
| 3 | *(no separate LB controller needed — AKS uses the Azure cloud-controller-manager)* |
| 4 | One `redpanda` namespace + one `<cluster>-multicluster-peer` Internal Standard LB Service per cluster (port 9443) |

## Prerequisites

- Terraform ≥ 1.6
- `az` CLI authenticated (`az login` and `az account set --subscription <ID>`)
- `kubectl`, `helm`, `rpk` (with v26.2.1-beta.1 plugin) on PATH for steps 5+

## Apply

```bash
cd terraform/azure
terraform init
terraform apply
```

First apply takes ~15–20 minutes. AKS clusters provision in parallel; VNet peering and NSG rules are quick.

## Outputs

```bash
terraform output -raw kubectl_setup_commands | bash    # registers contexts: rp-east rp-west rp-eu
terraform output peer_lb_addresses                     # paste into multicluster.peers
terraform output aks_endpoints                         # paste into multicluster.apiServerExternalAddress
```

## Variables

| Var | Default | Notes |
|---|---|---|
| `clusters` | east/west/eu in eastus/westus2/westeurope with non-overlapping VNet/subnet/pod/service CIDRs | Azure VNets are regional — peering is required for cross-region |
| `kubernetes_version` | `1.31` | |
| `vm_size` | `Standard_D4s_v5` | |
| `node_count` | 3 | Per cluster |
| `cross_cluster_ports` | `[9443, 33145, 9093, 8082, 9644]` | |

## Destroy

```bash
terraform destroy
```

Order is automatic via the dependency graph: peer Services and their LBs first, then NSG rules, then VNet peerings, then AKS clusters, then VNets/subnets, then resource groups.

If `terraform destroy` hangs on a VNet peering, give it a minute — peering deletion is async on the Azure side and Terraform retries. If a destroy fails on a resource group with stranded resources, check the Azure portal for orphan internal LBs that the AKS cloud-controller-manager didn't clean up before AKS itself was deleted (rare but possible).

## Notes

- `network_plugin_mode = "overlay"` on Azure CNI gives every pod an IP from the cluster's overlay pod CIDR — this is what makes pods routable across peered VNets without burning subnet IPs at scale.
- `kube_admin_config` is used directly by Terraform's kubernetes provider for simplicity. In production you'd swap to AAD-integrated `kube_config` plus `kubelogin`.
- AKS internal Standard LB has no global access toggle (Azure VNet peering already gives you cross-region routability via the same private IP — it's not regional like GCP's internal LB).
