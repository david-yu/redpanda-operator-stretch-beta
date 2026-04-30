# Terraform — Azure/AKS failover region (Demo B step 3)

Adds a **fourth** AKS cluster in a separate Azure region on top of the main `azure/terraform/` stack, used by [Demo B](../../README.md#demo-b-regional-failure--temporary-failover-region-capacity-injection) to inject capacity during a regional outage.

> **Status: skeleton / TODO.** The GCP failover stack at [`gcp/terraform-failover/`](../../gcp/terraform-failover/README.md) is fully implemented and validated. The Azure variant is captured here as a recipe — the resources to create are listed below; the `.tf` files mirror the main `azure/terraform/` stack with one extra region.

## What the stack should do

The Azure networking model (regional VNets with full-mesh peering) means adding a 4th region requires a 4th VNet plus **three** new bidirectional VNet peerings (one to each existing region):

| Resource | Notes |
|---|---|
| `azurerm_resource_group.failover` | New RG in the failover region (e.g. `centralus`) |
| `azurerm_virtual_network.failover` | CIDR not overlapping the existing 3 VNets (e.g. `10.40.0.0/16`) |
| `azurerm_subnet.failover_nodes` + `failover_pods` | Per-AZ subnets like the main stack |
| `azurerm_kubernetes_cluster.failover` | AKS cluster + default node pool, mirror the main stack |
| `azurerm_virtual_network_peering.failover_to_*` (×3) and `*_to_failover` (×3) | Six peerings total — VNet peering is unidirectional in Azure |
| `azurerm_network_security_rule.failover_cross_cluster` | Allow ports 9443/33145/9093/8082/9644 from the failover pod CIDR (and to it) on every cluster's NSG |
| `azurerm_kubernetes_*` for the operator peer LB Service | Mirror the main stack's pre-created LB Service |

## Recipe (manual, until the .tf is checked in)

The fastest manual fallback is `az aks create`:

```bash
az group create --name rp-failover-rg --location centralus
az aks create \
  --resource-group rp-failover-rg \
  --name rp-failover \
  --location centralus \
  --kubernetes-version 1.31 \
  --node-vm-size Standard_D4s_v5 \
  --node-count 3 \
  --network-plugin azure \
  --vnet-subnet-id <new-subnet-resource-id>
```

Create six VNet peerings (failover ↔ each of the 3 existing VNets, both directions) via the Azure portal or `az network vnet peering create`. Update each NSG to allow the new pod CIDR. Then continue with [Demo B step 4](../../README.md#demo-b-regional-failure--temporary-failover-region-capacity-injection).

## Apply (when implemented)

```bash
cd azure/terraform-failover
terraform init
terraform apply
```

## Outputs (planned)

```
failover_kubectl_setup_command   → updates kubeconfig + renames context to `rp-failover`
failover_peer_lb_address         → internal LB IP for multicluster.peers
failover_aks_fqdn                → for multicluster.apiServerExternalAddress (prefix with https://)
```
