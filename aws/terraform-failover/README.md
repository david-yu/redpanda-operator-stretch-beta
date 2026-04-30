# Terraform — AWS/EKS failover region (Demo B step 3)

Adds a **fourth** EKS cluster in a separate AWS region on top of the main `aws/terraform/` stack. Used by [Demo B](../../README.md#demo-b-regional-failure--temporary-failover-region-capacity-injection) to inject capacity when a primary region goes down: with RF=5 across 5 brokers, losing 2 of them blocks re-replication until 5 reachable brokers are back.

This stack is **independent** — it does not modify the main stack's terraform state. It uses `data` sources to look up the existing VPCs, TGWs, route tables, and EKS node SGs by tag/Name, then creates:

| Layer | What | Notes |
|---|---|---|
| Networking | New VPC + 3 private + 3 public subnets + NAT gateways | via `terraform-aws-modules/vpc/aws` |
| Compute | New EKS cluster + managed node group + EBS-CSI IRSA + gp2-default annotation | via `terraform-aws-modules/eks/aws` |
| Cross-region | New TGW in failover region, VPC attachment, **3 peering attachments** (failover ↔ each existing), accepters in the existing regions, **6 TGW routes** (3 in failover TGW, 3 in existing TGWs) | uses `aws.east` / `aws.west` / `aws.eu` provider aliases for the accepters and TGW route updates |
| VPC routes | Failover VPC route tables learn 3 existing CIDRs; each existing VPC's route tables learn the failover CIDR | the existing route tables are looked up via `aws_route_tables` data source on the existing VPC IDs |
| Security | Failover node SG ingress from existing CIDRs (and own CIDR for NLB SNAT); each existing node SG gains failover-CIDR ingress on the 5 stretch ports | existing node SGs looked up by `tag:Name = "<cluster>-node"` (the EKS module's default) |
| Bootstrap | redpanda namespace + peer LB Service (internal NLB via AWS LBC annotations) | the AWS LB Controller must be installed on the failover cluster — see note below |

> ⚠ **AWS LB Controller install.** The peer Service's internal-NLB annotations require the AWS Load Balancer Controller to be running on the failover cluster. The main `aws/terraform/lbc.tf` block installs it via Helm in each existing cluster, but this stack doesn't duplicate that — keeping the failover stack focused on networking + cluster, with operator/cert-manager/LBC layered on top by the user (Demo B step 4). If you skip the LBC install, the peer Service stays `Pending` and bootstrap fails. Two options: (a) `helm install aws-load-balancer-controller ...` against rp-failover by hand using the same chart version as the main stack (`var.lbc_chart_version` in `aws/terraform/variables.tf`), or (b) copy `aws/terraform/lbc.tf` into this stack and parameterize for the failover cluster.

## Prerequisites

- The main `aws/terraform/` stack already applied successfully (this stack looks up its TGWs/VPCs/SGs by tag)
- AWS credentials with permissions across all four regions (peering attachments are cross-region API calls — your principal needs to be allowed in each)
- `aws eks get-token` available locally for kubernetes provider exec auth

## Apply

```bash
cd aws/terraform-failover
terraform init
terraform apply
```

First apply takes ~12–18 min — EKS cluster + node group is the long pole; TGW peering accepters can also take a few minutes to settle.

## Outputs

```bash
terraform output -raw failover_kubectl_setup_command | bash    # registers context: rp-failover
terraform output failover_peer_lb_hostname                      # for multicluster.peers (AWS uses hostnames, not IPs)
terraform output -raw failover_eks_endpoint                     # for multicluster.apiServerExternalAddress
```

After this you continue with [Demo B step 4](../../README.md#demo-b-regional-failure--temporary-failover-region-capacity-injection) to bootstrap, install operator + cert-manager + LBC, and apply the failover NodePool.

## Variables

| Var | Default | Notes |
|---|---|---|
| `project_name` | `redpanda-stretch-validation` | Must match the main stack so we can find tagged resources |
| `failover_region` | `us-east-2` | Picked for low RTT (~12 ms) to the main stack's `us-east-1` |
| `failover_cluster_name` | `rp-failover` | Also the kubectl context alias after rename |
| `failover_vpc_cidr` | `10.40.0.0/16` | Must not overlap main stack's `10.{10,20,30}.0.0/16` |
| `failover_tgw_asn` | `64903` | Unique across the four TGW ASNs (main stack uses 64900–64902) |
| `existing_clusters` | east/us-east-1, west/us-west-2, eu/eu-west-1 with their CIDRs | Override if you customized the main stack's `clusters` map |
| `node_instance_type` | `m5.xlarge` | |
| `node_count` | `3` | |
| `cross_cluster_ports` | `[9443, 33145, 9093, 8082, 9644]` | Match the main stack |

## Destroy

```bash
terraform destroy
```

Destroys the failover EKS cluster, VPC, TGW, peering attachments + accepters, all six TGW routes, all VPC routes for the failover CIDR, the additive SG ingress rules on existing clusters, and the failover peer LB Service. The main stack is unaffected.

> Watch for the destroy hanging on the TGW peering attachments — AWS requires a few minutes between accepter delete and peering attachment delete. Terraform retries automatically.

## Notes

- The `aws_security_groups` data sources rely on the EKS module tagging the node SG with `Name = "<cluster>-node"`. If the main stack was customized (e.g. `node_security_group_name` overridden), update these in `data.tf`.
- The TGW ASN `64903` is unique across the four-TGW mesh. If you changed any of the main stack's TGW ASNs, check there's no collision.
- After `terraform destroy`, clean up the `rp-failover` kubectl context (`kubectl config delete-context rp-failover` — see step 4 in the root README's [Tear down](../../README.md#tear-down)).
