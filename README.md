# Redpanda Operator v26.2.1-beta.1 — Stretch Cluster on AWS, GCP, or Azure

A working, end-to-end deployment of a 3-region Redpanda **StretchCluster** managed by `operator/v26.2.1-beta.1`. Validated end-to-end on AWS EKS (Transit Gateway across `us-east-1`/`us-west-2`/`eu-west-1`); GCP and Azure Terraform configs follow the same pattern but have not yet been run end-to-end in this repo.

This repo captures the exact configs that brought a stretch cluster up green on first boot, plus the gotchas that aren't in the reference doc. The [original beta gist](https://gist.github.com/david-yu/41ea76df0cb4c84aad6483b1e95fcc32) is the conceptual reference; this repo's `terraform/`, `manifests/`, and `helm-values/` reflect the configs that actually work — see [Troubleshooting](#troubleshooting) for the why behind each one.

## Table of contents

- [Final state](#final-state)
- [Repo layout](#repo-layout)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
  - [Install the rpk-k8s plugin](#install-the-rpk-k8s-plugin)
- [Step-by-step](#step-by-step)
  - [1. Provision infrastructure (Terraform)](#1-provision-infrastructure-terraform)
  - [2. Bootstrap multicluster TLS + kubeconfig secrets](#2-bootstrap-multicluster-tls--kubeconfig-secrets)
  - [3. License Secret + helm install](#3-license-secret--helm-install)
  - [4. cert-manager per cluster](#4-cert-manager-per-cluster)
  - [5. Apply StretchCluster + NodePools](#5-apply-stretchcluster--nodepools)
  - [6. Wait for green](#6-wait-for-green)
- [Quick test — produce and consume across clusters](#quick-test--produce-and-consume-across-clusters)
- [Tear down](#tear-down)
- [Troubleshooting](#troubleshooting)
- [Cost (running)](#cost-running)
- [Source](#source)

## Final state

```
$ rpk k8s multicluster status --context rp-east --context rp-west --context rp-eu -n redpanda
CLUSTER  OPERATOR  RAFT-STATE     LEADER  PEERS  UNHEALTHY  TLS  SECRETS
rp-east  Running   StateFollower  rp-eu   3      0          ok   ok
rp-west  Running   StateFollower  rp-eu   3      0          ok   ok
rp-eu    Running   StateLeader    rp-eu   3      0          ok   ok

CROSS-CLUSTER:
  ✓ [unique-names] all node names are unique
  ✓ [peer-agreement] peer lists agree across all clusters
  ✓ [leader-agreement] leader agreement: rp-eu (term 2)
  ✓ [ca-consistency] all clusters share the same CA
```

```
$ kubectl --context rp-east -n redpanda exec sts/redpanda-rp-east -c redpanda -- rpk redpanda admin brokers list
ID    HOST                         PORT   RACK  CORES  MEMBERSHIP  IS-ALIVE  VERSION
0     redpanda-rp-east-0.redpanda  33145  -     1      active      true      25.3.14
1     redpanda-rp-eu-0.redpanda    33145  -     1      active      true      25.3.14
2     redpanda-rp-west-0.redpanda  33145  -     1      active      true      25.3.14
```

## Repo layout

```
terraform/aws/    — VPCs, EKS, Transit Gateway peering, AWS LB Controller, peer LB Services
terraform/gcp/    — Single global VPC + 3 regional subnets, GKE, firewall rules, peer LB Services
terraform/azure/  — VNets, AKS, full-mesh VNet peering, NSGs, peer LB Services
manifests/stretchcluster.yaml             — cloud-agnostic
manifests/nodepool-*.yaml                 — cloud-agnostic
helm-values/values-*.example.yaml         — cloud-agnostic; fill in placeholders before use
```

The `terraform/<cloud>/` directories are independent — pick one cloud and `terraform apply` against it. The remaining steps (manifests, helm values, bootstrap) are cloud-agnostic.

## Architecture

```
                 region 1 (rp-east)          region 2 (rp-west)         region 3 (rp-eu)
                ┌─────────────────────┐    ┌─────────────────────┐    ┌──────────────────────┐
operator pod    │ rp-east             │◀──▶│ rp-west             │◀──▶│ rp-eu (raft leader)  │
  raft :9443    │  └─ internal LB     │    │  └─ internal LB     │    │  └─ internal LB      │
broker pod      │ redpanda-rp-east-0  │    │ redpanda-rp-west-0  │    │ redpanda-rp-eu-0     │
  rpc    :33145 │     headless svc    │    │     headless svc    │    │     headless svc     │
  kafka  :9093  │     pod IP routable │    │     pod IP routable │    │     pod IP routable  │
                └─────────────────────┘    └─────────────────────┘    └──────────────────────┘
                              ▲                         ▲                          ▲
                              └───── cross-region L3 connectivity (full mesh) ─────┘
                                          AWS Transit Gateway
                                       │  GCP global VPC (no peering needed)
                                       │  Azure VNet peering full mesh
```

Two transports:
- **Operator-to-operator (raft, port 9443)** — internal cloud LB per cluster, addresses baked into TLS SANs by `rpk k8s multicluster bootstrap --loadbalancer`.
- **Broker-to-broker (RPC 33145, Kafka 9093)** — direct pod-IP routing. `networking.crossClusterMode: flat` makes the operator render headless Services and EndpointSlices populated with peer pod IPs. Routability comes from the cloud's L3 connectivity.

## Prerequisites

| Tool | Min version |
|---|---|
| Cloud CLI for your provider — `aws` / `gcloud` / `az` | latest stable |
| `terraform` | ≥ 1.6 |
| `kubectl` | matches your K8s version (1.31 here) |
| `helm` | ≥ 3.14 |
| `rpk` | with the v26.2.1-beta.1 `rpk-k8s` plugin (see below) |
| GCP only: `gke-gcloud-auth-plugin` | latest |

Plus a **Redpanda Enterprise license** — required, not optional. The multicluster operator binary won't start without one (see [Troubleshooting](#troubleshooting) issue 1).

### Install the `rpk-k8s` plugin

```bash
ARCH=darwin-arm64   # or linux-amd64, etc.
curl -sSLO "https://github.com/redpanda-data/redpanda-operator/releases/download/operator/v26.2.1-beta.1/rpk-k8s-${ARCH}-v26.2.1-beta.1.tar.gz"
tar -xzf "rpk-k8s-${ARCH}-v26.2.1-beta.1.tar.gz"
mkdir -p "$HOME/.local/bin"
install "rpk-k8s-${ARCH}" "$HOME/.local/bin/.rpk.ac-k8s"
export PATH="$HOME/.local/bin:$PATH"
rpk k8s multicluster --help
```

## Step-by-step

The flow: Terraform provisions infrastructure (step 1) → manual steps (2+) bootstrap multicluster, install the operator and StretchCluster. Steps 2 onward are cloud-agnostic — once the kubectl contexts `rp-east`, `rp-west`, `rp-eu` are registered, the same commands work on AWS, GCP, or Azure.

### 1. Provision infrastructure (Terraform)

Pick your cloud and follow the corresponding Terraform README — each handles VPCs/VNets, K8s clusters, cross-region networking, and pre-creates the peer LB Services for step 2:

| Cloud | Terraform | Networking model |
|---|---|---|
| **AWS / EKS** | [`terraform/aws/`](terraform/aws/README.md) | Transit Gateway with full-mesh inter-region peering |
| **GCP / GKE** | [`terraform/gcp/`](terraform/gcp/README.md) | Single global VPC with 3 regional subnets (no peering needed — GCP VPCs are global) |
| **Azure / AKS** | [`terraform/azure/`](terraform/azure/README.md) | 3 regional VNets with full-mesh VNet peering |

```bash
cd terraform/<aws|gcp|azure>
terraform init
terraform apply         # AWS / Azure
# or:
terraform apply -var project_id=<your-gcp-project>     # GCP
```

First apply takes ~15–25 minutes (control planes are the long pole; everything else is parallel).

Register the three clusters as kubectl contexts named `rp-east`, `rp-west`, `rp-eu`:

```bash
terraform output -raw kubectl_setup_commands | bash

# verify
for C in rp-east rp-west rp-eu; do
  kubectl --context "$C" get nodes
done
```

Capture the values needed by the next steps:

```bash
terraform output peer_lb_addresses    # GCP/Azure (IPs) — or peer_lb_hostnames on AWS (NLB DNS names)
terraform output -raw kubectl_setup_commands   # for reference
```

### 2. Bootstrap multicluster TLS + kubeconfig secrets

```bash
rpk k8s multicluster bootstrap \
  --context rp-east --context rp-west --context rp-eu \
  --namespace redpanda \
  --loadbalancer \
  --loadbalancer-timeout 10m
```

Bootstrap reuses the peer LB Services that Terraform pre-created (its `CreateOrUpdate` preserves the cloud-specific annotations). It emits a ready-to-paste `multicluster.peers` block.

Render per-cluster helm values from the example templates and substitute the peer addresses + cluster API endpoints:

```bash
for C in rp-east rp-west rp-eu; do
  cp helm-values/values-${C}.example.yaml /tmp/values-${C}.yaml
done

# Substitute the API server endpoint per cluster.
# AWS:    aws eks describe-cluster --region <r> --name <c> --query cluster.endpoint --output text
# GCP:    https://$(gcloud container clusters describe <c> --region <r> --format='value(endpoint)')
# Azure:  az aks show -n <c> -g <c>-rg --query fqdn -o tsv  (prefix with https://)

# And the peer LB hostnames/IPs (whichever your cloud emitted) into the three peers entries.
# AWS uses hostnames, GCP and Azure use IPs.
```

The example values use `<RP_EAST_API_SERVER>`, `<RP_EAST_NLB_HOSTNAME>`, etc. as placeholders — replace them with what `terraform output` emitted.

### 3. License Secret + helm install

The license itself is **never committed**. Place your license at a local path and create the Secret per cluster:

```bash
export RP_LICENSE=/path/to/redpanda.license   # not in this repo

for C in rp-east rp-west rp-eu; do
  kubectl --context "$C" -n redpanda create secret generic redpanda-license \
    --from-file=license.key="$RP_LICENSE" \
    --dry-run=client -o yaml | kubectl --context "$C" apply -f -
done

helm repo add redpanda https://charts.redpanda.com --force-update && helm repo update

for C in rp-east rp-west rp-eu; do
  helm --kube-context "$C" upgrade --install \
    "$C" redpanda/operator \
    --namespace redpanda \
    --version 26.2.1-beta.1 --devel \
    -f /tmp/values-${C}.yaml \
    --wait --timeout 5m &
done
wait
```

Note the **helm release name == cluster context name**. This makes the chart's `operator.Fullname` equal the context name, which keeps the bootstrap-created TLS Secret name (`<ctx>-multicluster-certificates`) aligned with what the chart looks up. Avoids the trap of needing `--name-override` (which collides peer names — see issue 4).

Confirm:

```bash
rpk k8s multicluster status --context rp-east --context rp-west --context rp-eu -n redpanda
```

You should see `OPERATOR=Running`, one cluster as `StateLeader`, all `PEERS=3`, `UNHEALTHY=0`, and the four cross-cluster checks ✓.

### 4. cert-manager per cluster

Required because `tls.enabled: true` on the StretchCluster spec triggers the operator to create cert-manager `Certificate` and `Issuer` resources. The original gist treats cert-manager as optional — that's wrong for any TLS-enabled deployment. cert-manager is independent of steps 1–3 and can be installed any time before step 5 (in parallel if you want to save wall-clock time).

```bash
helm repo add jetstack https://charts.jetstack.io --force-update && helm repo update

for C in rp-east rp-west rp-eu; do
  helm --kube-context "$C" upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager --create-namespace \
    --version v1.17.2 \
    --set crds.enabled=true \
    --wait --timeout 5m &
done
wait
```

### 5. Apply StretchCluster + NodePools

(Terraform already annotates the default StorageClass on AWS — `gp2`. GKE and AKS ship a default already; no patch needed.)

Apply the StretchCluster (identical on every cluster):

```bash
for C in rp-east rp-west rp-eu; do
  kubectl --context "$C" -n redpanda apply -f manifests/stretchcluster.yaml
done
```

Apply each NodePool to its own cluster:

```bash
kubectl --context rp-east -n redpanda apply -f manifests/nodepool-rp-east.yaml
kubectl --context rp-west -n redpanda apply -f manifests/nodepool-rp-west.yaml
kubectl --context rp-eu   -n redpanda apply -f manifests/nodepool-rp-eu.yaml
```

The StretchCluster spec uses **`networking.crossClusterMode: flat`** (operator manages headless Services + EndpointSlices with peer pod IPs — appropriate when the cloud gives you direct pod-to-pod routability across regions, which all three providers do here), and each NodePool has **`services.perPod.remote.enabled: true`** (so per-pool Services get rendered for remote pools too — required so peer DNS lookups resolve). Both differ from the gist; see [Troubleshooting](#troubleshooting) issues 7–8.

### 6. Wait for green

```bash
kubectl --context rp-east -n redpanda get stretchcluster redpanda \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}'
```

Want to see all of: `Ready=True`, `Healthy=True`, `LicenseValid=True`, `ResourcesSynced=True`, `ConfigurationApplied=True`, `SpecSynced=True`. (`Stable` and `Quiesced` may report `False` for a few minutes after a config change — that's normal.)

## Quick test — produce and consume across clusters

Verify Kafka actually works end-to-end across the three clusters:

```bash
# Create a topic with one replica per cluster
kubectl --context rp-east -n redpanda exec sts/redpanda-rp-east -c redpanda -- \
  rpk topic create stretch-test --partitions 6 --replicas 3

# Confirm replicas span all 3 brokers
kubectl --context rp-east -n redpanda exec sts/redpanda-rp-east -c redpanda -- \
  rpk topic describe stretch-test -p
# Expect REPLICAS=[0 1 2] on every partition.

# Produce keyed messages from rp-eu (Kafka controller cluster)
kubectl --context rp-eu -n redpanda exec sts/redpanda-rp-eu -c redpanda -- \
  bash -c 'for i in $(seq 1 9); do printf "k%d\thello-%d\n" $i $i; done | rpk topic produce stretch-test --format "%k\t%v\n"'

# Consume from a different cluster (rp-east)
kubectl --context rp-east -n redpanda exec sts/redpanda-rp-east -c redpanda -- \
  rpk topic consume stretch-test -n 9 -o start --format "p=%p o=%o k=%k v=%v\n"

# Consumer-group offsets persist across the cluster (run from a third cluster)
kubectl --context rp-west -n redpanda exec sts/redpanda-rp-west -c redpanda -- \
  rpk topic consume stretch-test -g cross-cluster-test -o start \
  --format "p=%p o=%o k=%k v=%v\n" -n 9

kubectl --context rp-east -n redpanda exec sts/redpanda-rp-east -c redpanda -- \
  rpk group describe cross-cluster-test
# Expect TOTAL-LAG=0 and per-partition CURRENT-OFFSET == LOG-END-OFFSET.
```

If any of these fail with `i/o timeout` or `dial tcp ...: connect: connection refused`, jump to issue 10 below — it's almost always a missing firewall/SG rule.

## Tear down

Workload first (StretchCluster has a deletion finalizer that needs every cluster reachable), then helm releases, then `terraform destroy` for the infrastructure:

```bash
# 1. Delete StretchCluster on every cluster.
for C in rp-east rp-west rp-eu; do
  kubectl --context "$C" -n redpanda delete stretchcluster redpanda --wait=false
done
for C in rp-east rp-west rp-eu; do
  kubectl --context "$C" -n redpanda wait --for=delete stretchcluster/redpanda --timeout=10m
done

# 2. Uninstall the operator + cert-manager helm releases.
for C in rp-east rp-west rp-eu; do
  helm --kube-context "$C" uninstall "$C" -n redpanda
  helm --kube-context "$C" uninstall cert-manager -n cert-manager
done

# 3. Tear down infrastructure with Terraform.
cd terraform/<aws|gcp|azure>
terraform destroy
# (GCP: terraform destroy -var project_id=<your-gcp-project>)
```

Cloud-specific notes:

- **AWS**: `terraform destroy` removes EKS clusters, VPCs, TGWs and peerings, NSG rules, AWS LBC IRSA, and the IAM policy. If destroy hangs on a TGW peering attachment, give it 2–3 minutes — peering deletion is async on the AWS side and Terraform retries. If a destroy hangs on a VPC, an unmanaged ENI from a leftover NLB is usually the cause; check the AWS console for stranded ELBv2 resources tagged with the project name.
- **GCP**: `terraform destroy` removes GKE clusters, the global VPC, regional subnets, Cloud NAT/Router, and firewall rules. Destroy is generally clean.
- **Azure**: `terraform destroy` removes AKS, VNets, peerings, NSGs, and resource groups. If a resource group destroy hangs, check the Azure portal for orphan internal LBs that the AKS cloud-controller-manager didn't clean up before AKS itself was deleted (rare but possible — usually `terraform destroy` retries through it).

In all three clouds, the recommended belt-and-braces sanity check after destroy is to look for any resources tagged with `Project=redpanda-stretch-validation` (or the value of `var.project_name`) and confirm none are left behind.

## Troubleshooting

### 1. Operator pod CrashLoopBackOff with "failed to read license file: open : no such file or directory"

The multicluster operator binary calls `license.ReadLicense(LicenseFilePath)` unconditionally (`operator/cmd/multicluster/multicluster.go:210`) and crashes on empty path. Redpanda's built-in 30-day broker trial does not cover the operator. You need a signed enterprise license loaded into a Secret and referenced via `enterprise.licenseSecretRef` in the helm values.

### 2. Peers can't connect: "connection refused" on operator pods

If your firewall/SG opens `8443` instead of `9443`, peer raft traffic is blocked. The operator listens for raft on **9443** (`PeerLoadBalancerPort` in `pkg/multicluster/bootstrap/loadbalancer.go`). Check:

```bash
# AWS
aws ec2 describe-security-groups --region <r> --group-ids <node-sg> \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`9443`]'
# GCP
gcloud compute firewall-rules describe redpanda-stretch-validation-cross-cluster
# Azure
az network nsg rule list -g <c>-rg --nsg-name <c>-nsg -o table
```

### 3. LB ends up internet-facing instead of internal

Bootstrap with `--loadbalancer` creates a vanilla `LoadBalancer` Service without cloud-specific annotations. The CLI has no `--annotations` flag; the underlying `PeerLoadBalancerConfig.Annotations` field is never populated from the CLI. **Pre-create the Service** with the right cloud-specific annotation (Terraform's `peer_services.tf` does this for you on every cloud — `aws-load-balancer-scheme: internal` for AWS, `networking.gke.io/load-balancer-type: Internal` for GCP, `azure-load-balancer-internal: "true"` for Azure), then run bootstrap — `controllerutil.CreateOrUpdate` reuses the existing Service and preserves your annotations.

### 4. Operator pods crashloop after install with "duplicate peer name" / raft can't form

Symptom: bootstrap output shows all peers with `name: redpanda-operator` (or whatever you passed to `--name-override`). The chart renders `--peer=<same>://addr1 --peer=<same>://addr2 --peer=<same>://addr3` and raft can't disambiguate. Fix: drop `--name-override` and use **per-cluster helm release names equal to the context name** plus `fullnameOverride: <ctx>` in values. The cluster.Name then carries the context name (unique) and the cert Secret name (`<ctx>-multicluster-certificates`) lines up with what the chart looks for via `operator.Fullname`.

### 5. helm install fails: "apiServerExternalAddress must be specified in multicluster mode"

Chart template-time check. Set it in values:

```yaml
multicluster:
  apiServerExternalAddress: https://<cluster-api-endpoint>
```

Get it via `terraform output eks_endpoints` / `gke_endpoints` / `aks_endpoints` depending on cloud, or:

```bash
# AWS
aws eks describe-cluster --region <r> --name <c> --query cluster.endpoint --output text
# GCP
gcloud container clusters describe <c> --region <r> --format='value(endpoint)'
# Azure
az aks show -n <c> -g <c>-rg --query fqdn -o tsv
```

### 6. Broker pods stuck `Init:0/3` with "MountVolume.SetUp failed for volume redpanda-default-cert: secret not found"

The operator created `redpanda-default-root-certificate` (CA) and the cert-manager `Certificate`/`Issuer` resources, but cert-manager itself isn't installed, so the leaf cert Secrets `redpanda-default-cert` and `redpanda-external-cert` never exist. Install cert-manager (step 4 above), then either wait or force-replace the stuck pods (`kubectl delete pod redpanda-<pool>-0 --grace-period=0 --force`) so kubelet retries the mount.

### 7. Brokers running but never become Ready (cluster_discovery loop)

Broker logs spam:
```
WARN cluster - cluster_discovery.cc:262 - Error requesting cluster bootstrap info from {host: redpanda-rp-west-0.redpanda, port: 33145}, retrying. (error C-Ares:4, redpanda-rp-west-0.redpanda: Not found)
```

This is the in-pod resolver (CoreDNS in cluster A) failing to resolve the short DNS name of a pod that lives in cluster B. Default cross-cluster mode is `mesh` (assumes Cilium ClusterMesh or similar). For an L3-only setup (TGW / GCP global VPC / Azure VNet peering) you want **`flat`**:

```yaml
spec:
  networking:
    crossClusterMode: flat
```

In flat mode the operator renders headless Services and manages EndpointSlices with peer pod IPs from across clusters, so DNS in any cluster resolves `redpanda-rp-west-0.redpanda` to the actual pod IP via your cloud's L3 path.

### 8. `flat` mode set but per-pool Services for remote pools don't exist

Symptom: `kubectl get svc -n redpanda` in `rp-east` shows only `redpanda-rp-east-0`, not `redpanda-rp-west-0` or `redpanda-rp-eu-0`. The operator is skipping rendering for remote pools because `services.perPod.remote.enabled: false` (the gist's value). Set it to `true` in every NodePool.

### 9. StretchCluster `ResourcesSynced=False`: "spec.clusterIPs[0]: Invalid value: ['None']: may not change once set"

The operator wants to convert per-pod Services to headless (clusterIP=None) for flat mode, but K8s doesn't allow changing `spec.clusterIP` after creation. Delete the affected Services (`kubectl delete svc redpanda-rp-{east,west,eu}-0 -n redpanda` on every cluster); the operator immediately recreates them headless on the next reconcile.

### 10. `rpk topic create` from inside a broker pod hangs / "i/o timeout" on port 9093

Kafka client port `9093` (and Pandaproxy `8082`, Admin `9644`) are not open across cluster CIDRs in firewall/NSG rules by default. The original gist only mentions `33145`. The Terraform in this repo opens all five via the `cross_cluster_ports` variable on every cloud (see `terraform/aws/sg.tf`, `terraform/gcp/firewall.tf`, `terraform/azure/nsg.tf`).

### 11. PVC `Pending`: "0/3 nodes are available: pod has unbound immediate PersistentVolumeClaims"

Cluster has no default StorageClass. Cloud-specific defaults:
- **AWS / EKS**: newer EKS doesn't ship `gp2` annotated default — `terraform/aws/eks.tf` patches `gp2` as default automatically.
- **GCP / GKE**: `standard-rwo` is default out of the box.
- **Azure / AKS**: `default` (Azure Managed Disks) is default out of the box.

If the PVC was created **before** the default class annotation existed, delete the stuck PVC and pod so they get recreated picking up the new default:
```bash
kubectl --context <c> -n redpanda delete pvc datadir-redpanda-<pool>-0
kubectl --context <c> -n redpanda delete pod redpanda-<pool>-0 --grace-period=0 --force
```

### 12. Bootstrap reports old peer addresses after re-running

`rpk k8s multicluster bootstrap` is idempotent. If you change the per-cluster Service name (e.g. moved from `redpanda-operator-multicluster-peer` to `<ctx>-multicluster-peer`), the previous bootstrap's TLS Secret and kubeconfig Secrets remain in the namespace under their old names. Clean them up explicitly before re-running:

```bash
for C in rp-east rp-west rp-eu; do
  kubectl --context "$C" -n redpanda delete secret \
    --selector=operator.redpanda.com/bootstrap-managed=true 2>/dev/null
  # And anything matching your old prefix
done
```

## Cost (running)

- **AWS**: 3× EKS control plane + 9× m5.xlarge + 3× internal NLB + TGW (3 attachments + 3 inter-region peerings) ≈ **$2.10/hr** at on-demand pricing, plus inter-region data transfer.
- **GCP**: 3× regional GKE control plane (free below 1 zonal cluster, ~$0.10/hr above) + 9× n2-standard-4 (~$0.19/hr each) + 3× internal LB (negligible idle) + 3× Cloud NAT + Router ≈ **~$2.00/hr**, plus inter-region egress.
- **Azure**: 3× AKS control plane (free with paid SKU) + 9× Standard_D4s_v5 (~$0.19/hr each) + 3× internal Standard LB ≈ **~$1.80/hr**, plus VNet peering + cross-region transfer.

Tear down promptly when validation is done.

## Source

This repo was generated during a one-shot validation run of `operator/v26.2.1-beta.1` on AWS. The reference doc is the [original beta gist](https://gist.github.com/david-yu/41ea76df0cb4c84aad6483b1e95fcc32). Issues found during validation are tracked above.
