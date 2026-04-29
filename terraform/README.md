# Terraform — steps 1–4

Provisions everything the stretch cluster needs **before** `rpk k8s multicluster bootstrap`:

| Step | Resource |
|---|---|
| 1 | 3× EKS clusters (one per region) with VPC, private subnets, NAT gateways, EBS CSI driver IRSA, and `gp2` annotated as the default StorageClass |
| 2 | 3× Transit Gateways, 3× VPC attachments, 3× inter-region peering attachments (full mesh), TGW + VPC route tables, security group ingress rules for ports 9443/33145/9093/8082/9644 across peer CIDRs |
| 3 | AWS Load Balancer Controller (helm) + IRSA role per cluster |
| 4 | One `redpanda` namespace + one `<cluster>-multicluster-peer` LoadBalancer Service per cluster (NLB internal, port 9443) |

## Prerequisites

- Terraform ≥ 1.6
- AWS credentials with permissions to create EKS, VPC, TGW, IAM, and ELBv2 resources
- `kubectl`, `helm`, `aws` CLI on PATH (the providers shell out to `aws eks get-token`)

## Apply

```bash
cd terraform
terraform init
terraform apply
```

First apply takes ~20–25 minutes (EKS control planes are the long pole; everything else runs in parallel).

## Outputs

After apply, Terraform prints:
- `cluster_names` / `regions` — for `aws eks update-kubeconfig`
- `eks_endpoints` — paste into `multicluster.apiServerExternalAddress` in helm values
- `peer_lb_hostnames` — paste into `multicluster.peers` in helm values
- `kubectl_setup_commands` — copy/paste these to register the three clusters as kubectl contexts named `rp-east`, `rp-west`, `rp-eu`

```bash
terraform output -raw kubectl_setup_commands | bash
```

After that you have everything you need for steps 5+ in the root README (`rpk k8s multicluster bootstrap`, helm install operator, apply StretchCluster + NodePools).

## Variables

See [variables.tf](variables.tf). Defaults match the validation run in the root README:

| Var | Default | Notes |
|---|---|---|
| `clusters` | east/west/eu in us-east-1/us-west-2/eu-west-1 with CIDRs 10.10/10.20/10.30 | CIDRs must be non-overlapping (TGW peering hard requirement) |
| `kubernetes_version` | `1.31` | |
| `node_instance_type` | `m5.xlarge` | |
| `node_count` | 3 | Per cluster |
| `cross_cluster_ports` | `[9443, 33145, 9093, 8082, 9644]` | Operator raft, broker RPC, Kafka, Pandaproxy, Admin API |
| `lbc_chart_version` | `1.13.0` | |

## Destroy

```bash
terraform destroy
```

Order is automatic via the dependency graph: peer Services first (releases NLBs via the LB Controller while it's still running), then helm releases, then EKS clusters and IAM roles, then TGW peerings + attachments + TGWs, then VPCs.

If a destroy hangs on TGW peering attachments, give it 2–3 minutes — peering deletion is async on the AWS side. If a destroy hangs on a VPC, check that no NLBs/ENIs are still attached (rare, but happens if the LB Controller helm uninstall finishes before its Services do; usually `terraform destroy` retries through it).

## Files

```
versions.tf         — provider version constraints
variables.tf        — input variables
locals.tf           — derived values
providers.tf        — multi-region AWS, multi-cluster k8s/helm aliases
vpc.tf              — 3 VPCs (terraform-aws-modules/vpc/aws)
eks.tf              — 3 EKS clusters (terraform-aws-modules/eks/aws) + EBS CSI IRSA + gp2 default
tgw.tf              — TGWs, peerings, route table associations, static routes
sg.tf               — cross-cluster SG ingress rules
lbc.tf              — AWS LB Controller IRSA + helm
peer_services.tf    — redpanda namespace + peer LB Service per cluster
outputs.tf          — endpoints and NLB hostnames for downstream steps
```
