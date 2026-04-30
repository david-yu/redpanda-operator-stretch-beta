# Terraform — AWS/EKS failover region (Demo B step 3)

Adds a **fourth** EKS cluster in a separate AWS region on top of the main `aws/terraform/` stack, used by [Demo B](../../README.md#demo-b-regional-failure--temporary-failover-region-capacity-injection) to inject capacity during a regional outage.

> **Status: skeleton / TODO.** The GCP failover stack at [`gcp/terraform-failover/`](../../gcp/terraform-failover/README.md) is fully implemented and validated. The AWS variant is captured here as a recipe — the resources to create are listed below; the `.tf` files mirror the main `aws/terraform/` stack with one extra region.

## What the stack should do

The AWS networking model (Transit Gateway with full-mesh inter-region peering) is more involved than GCP's global VPC, so adding a 4th region means adding a 4th VPC, a 4th TGW attachment, and **three** new TGW peering attachments (failover ↔ each existing region). Concretely:

| Resource | Notes |
|---|---|
| `aws_vpc.failover` | New VPC in the failover region (e.g. `us-east-2`), CIDR not overlapping the existing 3 VPCs (e.g. `10.40.0.0/16`) |
| `aws_subnet.failover_*` | Public + private subnets across 3 AZs, like the main stack |
| `aws_eks_cluster.failover` + managed node group | Mirror the main stack |
| `aws_ec2_transit_gateway.failover` | New TGW in the failover region |
| `aws_ec2_transit_gateway_vpc_attachment.failover` | Attach failover VPC to its TGW |
| `aws_ec2_transit_gateway_peering_attachment.failover_to_*` | Three peering attachments — failover ↔ east, failover ↔ west, failover ↔ eu |
| Route-table updates | Add routes for failover CIDR in the existing 3 regions' route tables; vice versa |
| `aws_security_group_rule.failover_cross_cluster` | Allow ports 9443/33145/9093/8082/9644 from the failover pod CIDR (and to the failover pod CIDR) on every cluster's worker SG |
| `aws_lb.failover_peer` (via Service annotation) | Internal NLB for the operator peer Service |

## Recipe (manual, until the .tf is checked in)

The fastest manual fallback is `eksctl`:

```bash
eksctl create cluster \
  --name rp-failover \
  --region us-east-2 \
  --version 1.31 \
  --nodegroup-name default \
  --node-type m5.xlarge \
  --nodes 3
```

Then attach the new VPC to the existing TGW and create three peering attachments by hand in the AWS console (or via `aws ec2` CLI). After connectivity is confirmed (`nc -vz` between pods), continue with [Demo B step 4](../../README.md#demo-b-regional-failure--temporary-failover-region-capacity-injection).

## Apply (when implemented)

```bash
cd aws/terraform-failover
terraform init
terraform apply
```

## Outputs (planned)

```
failover_kubectl_setup_command   → updates kubeconfig + renames context to `rp-failover`
failover_peer_lb_hostname        → NLB DNS name for multicluster.peers
failover_eks_endpoint            → for multicluster.apiServerExternalAddress
```
