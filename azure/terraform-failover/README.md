# Terraform — Azure/AKS failover region (Demo B step 3)

Adds a **fourth** AKS cluster in a separate Azure region on top of the main `azure/terraform/` stack. Used by [Demo B](../../README.md#demo-b-regional-failure--temporary-failover-region-capacity-injection) to inject capacity when a primary region goes down: with RF=5 across 5 brokers, losing 2 of them blocks re-replication until 5 reachable brokers are back.

This stack is **independent** — it does not modify the main stack's terraform state. It uses `data` sources to look up the existing resource groups, VNets, and NSGs by name, then creates:

| Layer | What |
|---|---|
| Networking | New resource group + VNet + node subnet |
| Compute | New AKS cluster (Azure CNI overlay) + system-assigned identity + default node pool |
| Cross-region | **6 VNet peerings** (failover ↔ each existing × both directions) — Azure peering is unidirectional |
| Security | Failover NSG with cross-cluster port rules sourced from all 4 VNet CIDRs (own VNet + 3 peers); additive rules on each existing NSG sourced from the failover VNet CIDR |
| Bootstrap | redpanda namespace + peer LB Service (internal Standard LB via `azure-load-balancer-internal: "true"` annotation) |

## Prerequisites

- The main `azure/terraform/` stack already applied successfully (this stack looks up its resource groups/VNets/NSGs by name)
- Azure credentials with Contributor on the subscription (or at least the four resource groups: failover RG plus the three existing RGs for the cross-region peerings + NSG-rule additions)
- `kubelogin` not required for this stack — direct kube_config from `azurerm_kubernetes_cluster` is used for the kubernetes provider

## Apply

```bash
cd azure/terraform-failover
terraform init
terraform apply
```

First apply takes ~10–15 min — AKS cluster is the long pole; VNet peerings are quick.

## Outputs

```bash
terraform output -raw failover_kubectl_setup_command | bash    # registers context: rp-failover
terraform output failover_peer_lb_address                       # for multicluster.peers (internal LB IP)
echo "https://$(terraform output -raw failover_aks_fqdn)"        # for multicluster.apiServerExternalAddress
```

After this you continue with [Demo B step 4](../../README.md#demo-b-regional-failure--temporary-failover-region-capacity-injection) to bootstrap, install operator + cert-manager, and apply the failover NodePool.

## Variables

| Var | Default | Notes |
|---|---|---|
| `project_name` | `redpanda-stretch-validation` | Must match the main stack |
| `failover_region` | `centralus` | ~30 ms RTT to `eastus`, ~50 ms to `westus2` |
| `failover_cluster_name` | `rp-failover` | Also the kubectl context alias |
| `failover_vnet_cidr` | `10.40.0.0/16` | Must not overlap main stack's `10.{10,20,30}.0.0/16` |
| `failover_subnet_cidr` | `10.40.0.0/20` | |
| `failover_pod_cidr` | `10.140.0.0/16` | Must not overlap `10.{110,120,130}.0.0/16` |
| `failover_service_cidr` | `10.141.0.0/20` | Must not overlap `10.{111,121,131}.0.0/20` |
| `failover_dns_service_ip` | `10.141.0.10` | Must be inside `failover_service_cidr` |
| `existing_clusters` | east/eastus, west/westus2, eu/westeurope with their CIDRs | Override if you customized the main stack |
| `vm_size` | `Standard_D4s_v5` | |
| `node_count` | `3` | |
| `cross_cluster_ports` | `[9443, 33145, 9093, 8082, 9644]` | Match the main stack |

## Destroy

```bash
terraform destroy
```

Destroys the failover AKS cluster, VNet, RG, all six VNet peerings, the additive NSG rules on the existing NSGs, and the failover peer LB Service. The main stack is unaffected.

## Notes

- The data-source lookups assume the main stack's deterministic naming (`<cluster-name>-rg/-vnet/-nsg`). If you customized those resource names, update `data.tf` accordingly.
- NSG rule priorities in this stack start at 300, leaving room (200–290) for the main stack's existing rules. If your main stack uses higher priorities, override `failover_port_to_priority` and `existing_failover_priority` in `nsg.tf`.
- The peer Service uses `service.beta.kubernetes.io/azure-load-balancer-internal: "true"` so the AKS cloud-controller-manager creates an internal Standard LB. No add-on install required.
- After `terraform destroy`, clean up the `rp-failover` kubectl context (`kubectl config delete-context rp-failover` — see step 4 in the root README's [Tear down](../../README.md#tear-down)).
