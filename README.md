# Redpanda Operator v26.2.1-beta.1 — Stretch Cluster on AWS, GCP, or Azure

A working, end-to-end deployment of a 3-region Redpanda **StretchCluster** managed by `operator/v26.2.1-beta.1`. Validated end-to-end on AWS EKS (Transit Gateway across `us-east-1`/`us-west-2`/`eu-west-1`); GCP and Azure Terraform configs follow the same pattern but have not yet been run end-to-end in this repo.

This repo captures the exact configs that brought a stretch cluster up green on first boot, plus the gotchas that aren't in the reference doc. The `aws/`, `gcp/`, and `azure/` directories each bundle the terraform, manifests, and helm-values that actually work for that cloud — see [Troubleshooting](#troubleshooting) for the why behind each one.

## Table of contents

- [Repo layout](#repo-layout)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Step-by-step](#step-by-step)
  - [1. Provision infrastructure (Terraform)](#1-provision-infrastructure-terraform)
  - [2. Install the rpk-k8s plugin](#2-install-the-rpk-k8s-plugin)
  - [3. Bootstrap multicluster TLS + kubeconfig secrets](#3-bootstrap-multicluster-tls--kubeconfig-secrets)
  - [4. License Secret + helm install](#4-license-secret--helm-install)
  - [5. Install cert-manager per cluster](#5-install-cert-manager-per-cluster)
  - [6. Apply StretchCluster + NodePools](#6-apply-stretchcluster--nodepools)
  - [7. Wait for StretchCluster status conditions to go green](#7-wait-for-stretchcluster-status-conditions-to-go-green)
  - [8. Validate stretch cluster health using rpk k8s multicluster](#8-validate-stretch-cluster-health-using-rpk-k8s-multicluster)
  - [9. Quick test — produce and consume across clusters](#9-quick-test--produce-and-consume-across-clusters)
- [Optional demos](#optional-demos)
  - [Demo A: ordered leader pinning + region-failover fallback](#demo-a-ordered-leader-pinning--region-failover-fallback)
  - [Demo B: regional failure + temporary failover-region capacity injection](#demo-b-regional-failure--temporary-failover-region-capacity-injection)
- [Tear down](#tear-down)
- [Troubleshooting](#troubleshooting)
- [Cost (running)](#cost-running)

## Repo layout

```
aws/
  terraform/    — VPCs, EKS, Transit Gateway peering, AWS LB Controller, peer LB Services
  manifests/    — stretchcluster.yaml + nodepool-*.yaml (rack preference baked for AWS regions)
  helm-values/  — values-*.example.yaml; fill in <PLACEHOLDER>s before use
gcp/
  terraform/    — Single global VPC + 3 regional subnets, GKE, firewall rules, peer LB Services
  manifests/    — stretchcluster.yaml + nodepool-*.yaml (rack preference baked for GCP regions)
  helm-values/  — values-*.example.yaml; fill in <PLACEHOLDER>s before use
azure/
  terraform/    — VNets, AKS, full-mesh VNet peering, NSGs, peer LB Services
  manifests/    — stretchcluster.yaml + nodepool-*.yaml (rack preference baked for Azure regions)
  helm-values/  — values-*.example.yaml; fill in <PLACEHOLDER>s before use
```

Each top-level cloud directory is self-contained — pick one cloud and run the full flow (terraform → bootstrap → helm install → manifests) from inside it. The nodepool manifests are cloud-agnostic; the only cloud-specific manifest difference is the `default_leaders_preference` rack list in `stretchcluster.yaml`, which uses the GKE/EKS/AKS-specific `topology.kubernetes.io/region` label values for that cloud.

## Architecture

<p align="center">
  <img src="docs/architecture.svg" alt="Redpanda StretchCluster 3-region topology — operator raft (LB-mediated) plus broker mesh (direct pod IP) over cloud L3 connectivity" width="100%">
</p>

> **Reading the diagram.** Solid arrows are the **operator-to-operator raft** path (port 9443, mTLS, terminated at each region's internal LoadBalancer). Dashed arrows are **direct broker-to-broker** traffic — RPC :33145 and Kafka :9093 — which uses pod IPs (no LB hop) routed over the cloud's L3 mesh shown in the band below the regions. Both transports are full mesh among all three clusters.

Two transports:
- **Operator-to-operator (raft, port 9443)** — internal cloud LB per cluster, addresses baked into TLS SANs by `rpk k8s multicluster bootstrap --loadbalancer`.
- **Broker-to-broker (RPC 33145, Kafka 9093)** — direct pod-IP routing. `networking.crossClusterMode: flat` makes the operator render headless Services and EndpointSlices populated with peer pod IPs. Routability comes from the cloud's L3 connectivity.

### Broker layout: 2 / 2 / 1 with RF=5

Each NodePool sets a per-region broker count: `nodepool-rp-east.yaml` and `nodepool-rp-west.yaml` use `replicas: 2`, `nodepool-rp-eu.yaml` uses `replicas: 1` — five brokers total, deployed `2 / 2 / 1` across the three regions. The default replication factor for new topics is `5` (one replica per broker), and the controller raft also includes all five brokers, so both data and control-plane raft groups need a 3-of-5 majority to make progress.

The asymmetric `2 / 2 / 1` shape — instead of `2 / 2 / 2` or `1 / 1 / 1` — is the cheapest layout that survives **any single full-region outage** without losing quorum:

| Region lost | Brokers remaining | Quorum (need 3) |
|---|---|---|
| rp-east (2 gone) | `0 + 2 + 1` = **3** | ✓ exactly at threshold |
| rp-west (2 gone) | `2 + 0 + 1` = **3** | ✓ exactly at threshold |
| rp-eu (1 gone)   | `2 + 2 + 0` = **4** | ✓ comfortable margin |

The 1-broker `rp-eu` region acts as the **odd-vote tiebreaker** between the two larger regions. Losing it is cheap (you still have four brokers in two regions); losing either two-broker region drops to exactly the quorum minimum, so it's tolerated but tight — replication should already be caught up before a second failure can stack on top. A `1 / 1 / 1` cluster (RF=3) survives a single-region loss too, but with no spare capacity for a concurrent broker failure within a surviving region; `2 / 2 / 1` keeps a one-broker buffer in each large region.

`default_leaders_preference: "racks:<region1>,<region2>,<region3>"` on top of this layout further makes leadership land in the first listed region whenever possible, so steady-state read/write traffic stays inside one region's brokers (lowest latency); leaders only fall through to the second/third region during an outage, which is what [Demo A](#demo-a-ordered-leader-pinning--region-failover-fallback) exercises.

## Prerequisites

| Tool | Min version |
|---|---|
| Cloud CLI for your provider — `aws` / `gcloud` / `az` | latest stable |
| `terraform` | ≥ 1.6 |
| `kubectl` | matches your K8s version (1.31 here) |
| `helm` | ≥ 3.14 |
| `rpk` | base CLI; the v26.2.1-beta.1 `rpk-k8s` plugin is installed in step 2 |
| GCP only: `gke-gcloud-auth-plugin` | latest |

Plus a **Redpanda Enterprise license** — required, not optional. The multicluster operator binary won't start without one (see [Troubleshooting](#troubleshooting) issue 1).

## Step-by-step

The flow: Terraform provisions infrastructure (step 1) → install the rpk-k8s plugin (step 2) → manual steps (3+) bootstrap multicluster, install the operator and StretchCluster. Steps 2 onward are cloud-agnostic — once the kubectl contexts `rp-east`, `rp-west`, `rp-eu` are registered, the same commands work on AWS, GCP, or Azure.

### 1. Provision infrastructure (Terraform)

Pick your cloud and follow the corresponding Terraform README — each handles VPCs/VNets, K8s clusters, cross-region networking, and pre-creates the peer LB Services for step 3:

| Cloud | Terraform | Networking model |
|---|---|---|
| **AWS / EKS** | [`aws/terraform/`](aws/terraform/README.md) | Transit Gateway with full-mesh inter-region peering |
| **GCP / GKE** | [`gcp/terraform/`](gcp/terraform/README.md) | Single global VPC with 3 regional subnets (no peering needed — GCP VPCs are global) |
| **Azure / AKS** | [`azure/terraform/`](azure/terraform/README.md) | 3 regional VNets with full-mesh VNet peering |

```bash
cd <aws|gcp|azure>/terraform
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

### 2. Install the `rpk-k8s` plugin

The multicluster bootstrap, status, and config are driven by `rpk k8s multicluster`, which lives in a versioned plugin shipped alongside each operator release. Install the plugin matching the operator version (`v26.2.1-beta.1`):

```bash
ARCH=darwin-arm64   # or linux-amd64, etc.
curl -sSLO "https://github.com/redpanda-data/redpanda-operator/releases/download/operator/v26.2.1-beta.1/rpk-k8s-${ARCH}-v26.2.1-beta.1.tar.gz"
tar -xzf "rpk-k8s-${ARCH}-v26.2.1-beta.1.tar.gz"
mkdir -p "$HOME/.local/bin"
install "rpk-k8s-${ARCH}" "$HOME/.local/bin/.rpk.ac-k8s"
export PATH="$HOME/.local/bin:$PATH"
rpk k8s multicluster --help
```

### 3. Bootstrap multicluster TLS + kubeconfig secrets

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
  cp <cloud>/helm-values/values-${C}.example.yaml /tmp/values-${C}.yaml
done

# Substitute the API server endpoint per cluster.
# AWS:    aws eks describe-cluster --region <r> --name <c> --query cluster.endpoint --output text
# GCP:    https://$(gcloud container clusters describe <c> --region <r> --format='value(endpoint)')
# Azure:  az aks show -n <c> -g <c>-rg --query fqdn -o tsv  (prefix with https://)

# And the peer LB hostnames/IPs (whichever your cloud emitted) into the three peers entries.
# AWS uses hostnames, GCP and Azure use IPs.
```

The example values use `<RP_EAST_API_SERVER>`, `<RP_EAST_NLB_HOSTNAME>`, etc. as placeholders — replace them with what `terraform output` emitted.

### 4. License Secret + helm install

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

Note the **helm release name == cluster context name**. This makes the chart's `operator.Fullname` equal the context name, which keeps the bootstrap-created TLS Secret name (`<ctx>-multicluster-certificates`) aligned with what the chart looks up. Avoids the trap of needing `--name-override` (which collides peer names — see [Troubleshooting](#troubleshooting) issue 3).

Confirm:

```bash
rpk k8s multicluster status --context rp-east --context rp-west --context rp-eu -n redpanda
```

You should see `OPERATOR=Running`, one cluster as `StateLeader`, all `PEERS=3`, `UNHEALTHY=0`, and the four cross-cluster checks ✓.

### 5. Install cert-manager per cluster

Required because `tls.enabled: true` on the StretchCluster spec triggers the operator to create cert-manager `Certificate` and `Issuer` resources — without it, broker pods stay stuck in `Init` waiting for the leaf-cert Secrets to appear (see [Troubleshooting](#troubleshooting) issue 5). cert-manager is independent of steps 1–4 and can be installed any time before step 6 (in parallel if you want to save wall-clock time).

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

### 6. Apply StretchCluster + NodePools

(Terraform already annotates the default StorageClass on AWS — `gp2`. GKE and AKS ship a default already; no patch needed.)

The repo ships one `stretchcluster.yaml` and three `nodepool-rp-{east,west,eu}.yaml` per cloud. The StretchCluster CR is identical across the three K8s clusters (it's the cluster-wide Redpanda spec); each NodePool defines that cluster's slice of the broker fleet — `replicas: 2` for rp-east and rp-west, `replicas: 1` for rp-eu (the 2 / 2 / 1 quorum-tiebreaker shape — see [Broker layout](#broker-layout-2--2--1-with-rf5)).

**`<cloud>/manifests/stretchcluster.yaml`** (GCP example shown — AWS/Azure differ only in the `default_leaders_preference` rack list):

```yaml
apiVersion: cluster.redpanda.com/v1alpha2
kind: StretchCluster
metadata:
  name: redpanda
  namespace: redpanda
spec:
  rbac:
    enabled: true
  external:
    enabled: false
  networking:
    crossClusterMode: flat              # operator manages headless Services + EndpointSlices
  rackAwareness:
    enabled: true
    nodeAnnotation: topology.kubernetes.io/region   # rack = cloud region
  tls:
    enabled: true
    certs:
      default:
        caEnabled: true
  enterprise:
    licenseSecretRef:
      name: redpanda-license
      key: license.key
  config:
    cluster:
      # Ordered leader pinning — rack list is cloud-specific:
      #   AWS:   racks:us-east-1,us-west-2,eu-west-1
      #   GCP:   racks:us-east1,us-west1,us-east4
      #   Azure: racks:eastus,westus2,westeurope
      default_leaders_preference: "racks:us-east1,us-west1,us-east4"
      partition_autobalancing_node_availability_timeout_sec: 30   # demo-fast (default 900)
      partition_autobalancing_node_autodecommission_timeout_sec: 60   # demo-fast (default 600)
```

**`<cloud>/manifests/nodepool-rp-east.yaml`** (rp-west uses an identical shape with `name: rp-west`; rp-eu uses `replicas: 1`):

```yaml
apiVersion: cluster.redpanda.com/v1alpha2
kind: NodePool
metadata:
  name: rp-east
  namespace: redpanda
spec:
  clusterRef:
    group: cluster.redpanda.com
    kind: StretchCluster
    name: redpanda
  replicas: 2                           # rp-eu uses replicas: 1 (the tiebreaker)
  image:
    repository: redpandadata/redpanda
    tag: v26.1.6
  services:
    perPod:
      remote:
        enabled: true                   # required so per-pool Services for remote pools render
```

Apply the StretchCluster (identical on every cluster):

```bash
for C in rp-east rp-west rp-eu; do
  kubectl --context "$C" -n redpanda apply -f <cloud>/manifests/stretchcluster.yaml
done
```

Apply each NodePool to its own cluster:

```bash
kubectl --context rp-east -n redpanda apply -f <cloud>/manifests/nodepool-rp-east.yaml
kubectl --context rp-west -n redpanda apply -f <cloud>/manifests/nodepool-rp-west.yaml
kubectl --context rp-eu   -n redpanda apply -f <cloud>/manifests/nodepool-rp-eu.yaml
```

The StretchCluster spec uses **`networking.crossClusterMode: flat`** (operator manages headless Services + EndpointSlices with peer pod IPs — appropriate when the cloud gives you direct pod-to-pod routability across regions, which all three providers do here), and each NodePool has **`services.perPod.remote.enabled: true`** (so per-pool Services get rendered for remote pools too — required so peer DNS lookups resolve). See [Troubleshooting](#troubleshooting) issues 6–7 for the why behind each.

### 7. Wait for StretchCluster status conditions to go green

```bash
kubectl --context rp-east -n redpanda get stretchcluster redpanda \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}'
```

Want to see all of: `Ready=True`, `Healthy=True`, `LicenseValid=True`, `ResourcesSynced=True`, `ConfigurationApplied=True`, `SpecSynced=True`. (`Stable` and `Quiesced` may report `False` for a few minutes after a config change — that's normal.)

### 8. Validate stretch cluster health using `rpk k8s multicluster`

Two checks confirm the cluster is fully wired up — one for the operator/raft layer and one for the Redpanda data plane.

**Operator + cross-cluster raft.** `rpk k8s multicluster status` connects to every operator pod (one per K8s cluster) over the bootstrap-managed mTLS, prints the raft role each one currently holds, and runs four cross-cluster sanity checks: that no two operators picked the same node name, that all operators agree on which peers exist, that they all agree on who the raft leader is at the same term, and that they all carry the same shared CA. A healthy install reports `OPERATOR=Running` everywhere, exactly one `StateLeader` and the rest `StateFollower`, `PEERS=3`, `UNHEALTHY=0`, `TLS=ok`, `SECRETS=ok`, and ✓ on all four cross-cluster checks:

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

**Broker membership.** Once raft is healthy, the brokers themselves should have formed a single Redpanda cluster spanning the three K8s clusters. `rpk redpanda admin brokers list` (run inside any broker pod via `kubectl exec`) hits the local broker's Admin API and dumps the cluster's authoritative broker list. The point of running it from one region and seeing brokers in *all* regions is to confirm broker-to-broker discovery worked: the in-pod DNS resolved peer pod names like `redpanda-rp-west-0.redpanda` to actual cross-cluster pod IPs (via the operator's flat-mode EndpointSlices), traffic on port 33145 flowed through the cloud's L3 path (TGW / VPC / VNet peering), and the brokers gossiped successfully. Every row should show `MEMBERSHIP=active` and `IS-ALIVE=true`:

```
$ kubectl --context rp-east -n redpanda exec sts/redpanda-rp-east -c redpanda -- rpk redpanda admin brokers list
ID    HOST                         PORT   RACK  CORES  MEMBERSHIP  IS-ALIVE  VERSION
0     redpanda-rp-east-0.redpanda  33145  -     1      active      true      26.1.6
1     redpanda-rp-eu-0.redpanda    33145  -     1      active      true      26.1.6
2     redpanda-rp-west-0.redpanda  33145  -     1      active      true      26.1.6
```

If `rpk multicluster status` looks healthy but `brokers list` doesn't show all the expected brokers, suspect a broker-network problem (firewall/SG missing port 33145, or `crossClusterMode` not set to `flat`); see [Troubleshooting](#troubleshooting) issues 6 and 9.

### 9. Quick test — produce and consume across clusters

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

If any of these fail with `i/o timeout` or `dial tcp ...: connect: connection refused`, jump to issue 9 below — it's almost always a missing firewall/SG rule.

## Optional demos

The default `stretchcluster.yaml` enables two stretch-cluster-specific features: **rack awareness with ordered leader pinning** (so partition leaders land in your preferred region first) and **automatic broker decommissioning** (so a permanently-gone broker gets evicted from the cluster). Both demos below run end-to-end with **no extra `rpk cluster config set` steps** — the relevant cluster config keys are committed into `<cloud>/manifests/stretchcluster.yaml` and applied at deploy time.

The committed defaults are:

| Key | Value | Why |
|---|---|---|
| `default_leaders_preference` | `racks:us-east-1,us-west-2,eu-west-1` | Ordered leader pinning. |
| `partition_autobalancing_node_availability_timeout_sec` | `30` | Demo-fast (default 900s). |
| `partition_autobalancing_node_autodecommission_timeout_sec` | `60` | Demo-fast (default 600s). |

The autobalancer timeouts are tuned aggressively so the demos finish in 2–3 minutes. **Raise these substantially before using a stretch cluster in production** — a transient regional blip shouldn't trigger an automatic decommission.

Run both demos after step 9 (Quick test) on a healthy cluster.

### Demo A: ordered leader pinning + region-failover fallback

The committed `stretchcluster.yaml` configures:

```yaml
rackAwareness:
  enabled: true
  nodeAnnotation: topology.kubernetes.io/region   # rack = AWS region

config:
  cluster:
    # Ordered preference: prefer us-east-1; if it's unavailable, fall back
    # to us-west-2; only use eu-west-1 if both US regions are gone.
    default_leaders_preference: "racks:us-east-1,us-west-2,eu-west-1"
```

Each broker reads the K8s node's `topology.kubernetes.io/region` label and uses it as its rack — so brokers end up in racks `us-east-1`, `us-west-2`, `eu-west-1` (one rack per region). Verify:

```bash
kubectl --context rp-east -n redpanda exec sts/redpanda-rp-east -c redpanda -- \
  rpk redpanda admin brokers list
```

Expected output — every broker has a `RACK` value matching its region:

```
ID    HOST                         PORT   RACK       CORES  MEMBERSHIP  IS-ALIVE  VERSION
0     redpanda-rp-east-0.redpanda  33145  us-east-1  1      active      true      26.1.6
1     redpanda-rp-east-1.redpanda  33145  us-east-1  1      active      true      26.1.6
2     redpanda-rp-eu-0.redpanda    33145  eu-west-1  1      active      true      26.1.6
3     redpanda-rp-west-0.redpanda  33145  us-west-2  1      active      true      26.1.6
4     redpanda-rp-west-1.redpanda  33145  us-west-2  1      active      true      26.1.6
```

**Show preference 1 working** — create a topic with 12 partitions and watch leadership concentrate on `us-east-1` brokers:

```bash
kubectl --context rp-east -n redpanda exec sts/redpanda-rp-east -c redpanda -- \
  rpk topic create leader-pinning-demo --partitions 12 --replicas 5
```

```
TOPIC                STATUS
leader-pinning-demo  OK
```

```bash
sleep 60   # let the leader balancer converge
kubectl --context rp-east -n redpanda exec sts/redpanda-rp-east -c redpanda -- \
  rpk topic describe leader-pinning-demo -p
```

Expected partition table — every replica list contains all 5 brokers (RF=5), and every leader is broker 0 or 1:

```
PARTITION  LEADER  EPOCH  REPLICAS     LOG-START-OFFSET  HIGH-WATERMARK
0          0       2      [0 1 2 3 4]  0                 0
1          0       1      [0 1 2 3 4]  0                 0
2          0       2      [0 1 2 3 4]  0                 0
3          0       2      [0 1 2 3 4]  0                 0
4          1       2      [0 1 2 3 4]  0                 0
5          1       2      [0 1 2 3 4]  0                 0
6          1       2      [0 1 2 3 4]  0                 0
7          0       1      [0 1 2 3 4]  0                 0
8          0       2      [0 1 2 3 4]  0                 0
9          1       1      [0 1 2 3 4]  0                 0
10         1       2      [0 1 2 3 4]  0                 0
11         1       1      [0 1 2 3 4]  0                 0
```

A leader-by-broker tally makes the pattern obvious:

```bash
kubectl --context rp-east -n redpanda exec sts/redpanda-rp-east -c redpanda -- \
  rpk topic describe leader-pinning-demo -p | awk 'NR>1 {print $2}' | sort | uniq -c
```

```
   6 0
   6 1
```

— all 12 leaders on the two `us-east-1` brokers (preference 1), evenly split.

**Show fallback when us-east-1 goes down** — scale the rp-east StatefulSet to 0:

```bash
kubectl --context rp-east -n redpanda scale sts redpanda-rp-east --replicas=0
```

```
statefulset.apps/redpanda-rp-east scaled
```

```bash
# Wait ~90s for brokers to terminate, partitions to re-replicate, and the
# leader balancer to converge on the next-priority rack.
sleep 90

kubectl --context rp-west -n redpanda exec sts/redpanda-rp-west -c redpanda -- \
  rpk topic describe leader-pinning-demo -p | awk 'NR>1 {print $2}' | sort | uniq -c
```

Expected — leaders migrate off brokers 0+1 to brokers 3+4 (`us-west-2`, preference 2):

```
   6 3
   6 4
```

If during a transition you see something like:

```
   4 2
   4 3
   4 4
```

that's the leader balancer mid-convergence — broker 2 (`eu-west-1`, preference 3) was used as a temporary holder for partitions whose preferred replicas were not yet caught up. Wait another 30–60s and re-tally; leadership consolidates on `us-west-2` once partitions are re-replicated there.

**Restore us-east-1**:

```bash
kubectl --context rp-east -n redpanda scale sts redpanda-rp-east --replicas=2
```

```
statefulset.apps/redpanda-rp-east scaled
```

```bash
# Brokers rejoin (~60s), partitions catch up, leader balancer moves leaders
# back to us-east-1 (preference 1). Expect:
#    6 0
#    6 1
```

A few caveats observed during validation:

- The leader balancer **stalls during under-replicated periods** — when half a region's brokers go away, it pauses while the cluster is recovering, then resumes once partitions are re-replicated. Expect 30–90s of "leaders not yet on us-west-2" while replicas are being rebuilt elsewhere.
- Cross-region heartbeats can flap during transitions — `rpk redpanda admin brokers list` may briefly show un-affected brokers as `IS-ALIVE=false`. Confirm against `rpk cluster health` (`Nodes down:` field) which uses the controller's authoritative view.

### Demo B: regional failure + temporary failover-region capacity injection

The 2 / 2 / 1 broker layout with `RF=5` survives a single-region outage in terms of *quorum* (3 of 5 brokers remain), but it cannot *self-heal* RF: with `RF=5` and only 3 reachable brokers, the partition autobalancer has nowhere to rebuild the missing two replicas, so:

- The two brokers from the lost region get marked unavailable after `partition_autobalancing_node_availability_timeout_sec` (30s)
- Auto-decommission would normally start after `partition_autobalancing_node_autodecommission_timeout_sec` (60s), but it stalls (`partition_balancer/status: "stalled"`) because there's no way to rehome the replicas
- Brokers from the lost region stay in `draining`/`active` indefinitely, and every `RF=5` topic shows under-replicated partitions

The operational fix is to **add capacity in a fourth, separate failover region**. As soon as the cluster has 5 reachable brokers again, re-replication unblocks, the autobalancer drains the two lost brokers, and the cluster returns to RF=5 across the new layout. This demo walks through the full sequence: simulate the regional failure, observe the stall, deploy the failover region, watch recovery, then restore the primary and decommission the failover.

> ⚠ **More than just `kubectl` calls.** Unlike Demo A, this demo provisions a 4th K8s cluster (Terraform / `gcloud container clusters create` / `eksctl` / `az aks create`) and rolls a fresh helm release. Plan ~15-20 min of wall-clock and the additional infra cost while the failover region is up.

**Step 1 — simulate the regional failure**

```bash
kubectl --context rp-east -n redpanda scale sts redpanda-rp-east --replicas=0
```

After ~90s (30s availability + 60s autodecom timeouts), check broker state from a surviving region:

```bash
kubectl --context rp-west -n redpanda exec sts/redpanda-rp-west -c redpanda -- \
  rpk redpanda admin brokers list
```

```
ID  HOST                         RACK      MEMBERSHIP  IS-ALIVE
0   redpanda-rp-east-0.redpanda  us-east1  active      false
1   redpanda-rp-east-1.redpanda  us-east1  draining    false
2   redpanda-rp-eu-0.redpanda    us-east4  active      true
3   redpanda-rp-west-0.redpanda  us-west1  active      true
4   redpanda-rp-west-1.redpanda  us-west1  active      true
```

**Step 2 — confirm the partition autobalancer is stalled**

```bash
kubectl --context rp-west -n redpanda exec sts/redpanda-rp-west -c redpanda -- \
  rpk cluster health
```

```
Healthy:                          false
Unhealthy reasons:                [nodes_down under_replicated_partitions]
All nodes:                        [0 1 2 3 4]
Nodes down:                       [0 1]
Under-replicated partitions:      18      # all RF=5 topics across the cluster
```

The autobalancer status itself confirms the stall (admin API on any reachable broker):

```bash
kubectl --context rp-west -n redpanda exec sts/redpanda-rp-west -c redpanda -- \
  curl -ks --cacert /etc/tls/certs/default/ca.crt \
       --cert /etc/tls/certs/default/tls.crt --key /etc/tls/certs/default/tls.key \
  https://localhost:9644/v1/cluster/partition_balancer/status
```

```json
{
  "status": "stalled",
  "violations": { "unavailable_nodes": [0, 1] },
  "current_reassignments_count": 0
}
```

**Step 3 — provision a fourth K8s cluster + cross-region networking (rp-failover)**

The failover region needs three things: (a) a K8s cluster reachable from the existing clusters' pod CIDRs, (b) cross-region L3 routing extended to the failover pod CIDR, and (c) a pre-created internal-LB peer Service in the `redpanda` namespace. Each cloud provides a dedicated terraform stack that does all three; pick yours below. CIDRs in each stack default to non-overlapping ranges (`10.40.x.x` / `10.140.x.x` / `10.141.x.x` for failover) so it can be applied on top of the main stack without conflicts.

| Cloud | Failover terraform | What it does |
|---|---|---|
| **GCP / GKE** | [`gcp/terraform-failover/`](gcp/terraform-failover/README.md) | Looks up the existing global VPC by name, adds a 4th subnet + Cloud Router/NAT, creates a 4th GKE cluster, and adds an additive firewall rule that includes the failover pod CIDR. **Validated.** |
| **AWS / EKS** | [`aws/terraform-failover/`](aws/terraform-failover/README.md) | New VPC + EKS cluster, new TGW attachment, three TGW peering attachments (failover ↔ each existing region), route-table updates, SG rules. **Skeleton — recipe + manual `eksctl` fallback in the directory README.** |
| **Azure / AKS** | [`azure/terraform-failover/`](azure/terraform-failover/README.md) | New resource group + VNet + AKS cluster, six VNet peerings (failover ↔ each existing VNet, both directions), NSG rules. **Skeleton — recipe + manual `az aks create` fallback in the directory README.** |

```bash
# GCP — fully working, ~10–12 min
cd gcp/terraform-failover
terraform init
terraform apply -var project_id=<your-gcp-project>
terraform output -raw failover_kubectl_setup_command | bash    # registers context: rp-failover
terraform output failover_peer_lb_address                       # for multicluster.peers
terraform output -raw failover_gke_endpoint                     # for multicluster.apiServerExternalAddress

# AWS / Azure — until the .tf is checked in, follow the recipe in
#   aws/terraform-failover/README.md  or  azure/terraform-failover/README.md
```

**Step 4 — bootstrap, install, apply manifests on the failover cluster (cloud-agnostic)**

Once the rp-failover context is registered and the failover region's pod CIDR is reachable from the other three regions, the rest of the flow is identical to the original 3-cluster bring-up — just run it for the new cluster and update peer lists.

```bash
# Capture the addresses for the helm values templates (output names depend on the cloud:
# AWS uses peer hostnames, GCP/Azure use IPs)
RP_FAILOVER_API=$(terraform output -raw failover_gke_endpoint)
RP_FAILOVER_LB=$(terraform output -raw failover_peer_lb_address)

# 1. Bootstrap multicluster including the new cluster (idempotent — existing TLS state is preserved).
rpk k8s multicluster bootstrap \
  --context rp-east --context rp-west --context rp-eu --context rp-failover \
  --namespace redpanda --loadbalancer --loadbalancer-timeout 10m

# 2. Render an rp-failover values file from the existing template.
#    Edit /tmp/values-rp-failover.yaml to set:
#      multicluster.name: rp-failover
#      multicluster.apiServerExternalAddress: $RP_FAILOVER_API
#      multicluster.peers: 4 entries (rp-east, rp-west, rp-eu, rp-failover with $RP_FAILOVER_LB)
cp <cloud>/helm-values/values-rp-east.example.yaml /tmp/values-rp-failover.yaml
# (then sed/edit as above)

# 3. Update the OTHER three clusters' values to list 4 peers, helm upgrade so they learn the new peer.
#    /tmp/values-rp-{east,west,eu}.yaml → add the rp-failover peer entry, then:
for C in rp-east rp-west rp-eu; do
  helm --kube-context "$C" upgrade "$C" redpanda/operator \
    --namespace redpanda --version 26.2.1-beta.1 --devel \
    -f /tmp/values-${C}.yaml --wait --timeout 5m
done

# 4. License Secret + cert-manager + operator on rp-failover
kubectl --context rp-failover -n redpanda create secret generic redpanda-license \
  --from-file=license.key="$RP_LICENSE" --dry-run=client -o yaml \
  | kubectl --context rp-failover apply -f -

helm --kube-context rp-failover upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace --version v1.17.2 \
  --set crds.enabled=true --wait --timeout 5m

helm --kube-context rp-failover upgrade --install rp-failover redpanda/operator \
  --namespace redpanda --version 26.2.1-beta.1 --devel \
  -f /tmp/values-rp-failover.yaml --wait --timeout 5m

# 5. StretchCluster + a 2-broker NodePool on the failover cluster (use your cloud's manifests/)
kubectl --context rp-failover -n redpanda apply -f <cloud>/manifests/stretchcluster.yaml
cat <<'EOF' | kubectl --context rp-failover -n redpanda apply -f -
apiVersion: cluster.redpanda.com/v1alpha2
kind: NodePool
metadata: { name: rp-failover, namespace: redpanda }
spec:
  clusterRef: { group: cluster.redpanda.com, kind: StretchCluster, name: redpanda }
  replicas: 2
  image: { repository: redpandadata/redpanda, tag: v26.1.6 }
  services: { perPod: { remote: { enabled: true } } }
EOF
```

Confirm the operator joined the multicluster cleanly:

```bash
rpk k8s multicluster status --context rp-east --context rp-west --context rp-eu --context rp-failover --namespace redpanda
# Expect PEERS=4, UNHEALTHY=0, all 4 cross-cluster checks ✓
```

**Step 5 — watch recovery (~5–10 min)**

```bash
for i in $(seq 1 30); do
  echo "--- $(date +%T) ---"
  kubectl --context rp-west -n redpanda exec sts/redpanda-rp-west -c redpanda -- \
    rpk redpanda admin brokers list | awk 'NR>1 {print $1, $4, $6, $7}'
  sleep 30
done
```

Expected progression:

```
--- T+0:00 ---       # rp-failover brokers (5, 6) just joined; brokers 0, 1 still stuck
0 us-east1     active   false
1 us-east1     draining false
2 us-east4     active   true
3 us-west1     active   true
4 us-west1     active   true
5 us-central1  active   true
6 us-central1  active   true

--- T+5:00 ---       # autobalancer un-stalled (5 reachable brokers); drain progressing
0 us-east1     draining false
1 us-east1     draining false
2 us-east4     active   true
3 us-west1     active   true
4 us-west1     active   true
5 us-central1  active   true
6 us-central1  active   true

--- T+8:00 ---       # drain complete; brokers 0, 1 evicted; 5 active brokers again
2 us-east4     active   true
3 us-west1     active   true
4 us-west1     active   true
5 us-central1  active   true
6 us-central1  active   true
```

`rpk topic describe` should now show every RF=5 topic with replicas drawn from `[2 3 4 5 6]`:

```
PARTITION  LEADER  EPOCH  REPLICAS     LOG-START-OFFSET  HIGH-WATERMARK
0          3       4      [2 3 4 5 6]  0                 0
1          5       4      [2 3 4 5 6]  0                 0
...
```

`rpk cluster health` reports `Healthy: true` and `Under-replicated partitions: 0`, and `partition_balancer/status` returns `"status": "ready"`.

**Step 6 — restore the primary, let auto-decommission retire the failover brokers**

When us-east1 is back online, bring rp-east up:

```bash
kubectl --context rp-east -n redpanda scale sts redpanda-rp-east --replicas=2
```

Two new brokers join (IDs 7, 8) in rack `us-east1` and start picking up replicas. Once `Under-replicated partitions: 0` again — meaning the cluster has spare capacity in rack `us-east1` for replicas to migrate to — you can let auto-decommission retire the temporary failover brokers by simply tearing down their infrastructure:

```bash
# 1. Remove the failover NodePool, then the operator + cert-manager helm releases.
kubectl --context rp-failover -n redpanda delete nodepool rp-failover
helm --kube-context rp-failover uninstall rp-failover -n redpanda
helm --kube-context rp-failover uninstall cert-manager -n cert-manager

# 2. Destroy the failover infrastructure.
cd <aws|gcp|azure>/terraform-failover && terraform destroy
# (or `gcloud container clusters delete rp-failover --region us-central1` if you used the manual path)
```

Brokers 5 and 6 become unreachable as their pods + nodes go away; after `partition_autobalancing_node_availability_timeout_sec` (30 s) the controller marks them unavailable, and after `partition_autobalancing_node_autodecommission_timeout_sec` (60 s) the partition autobalancer issues the decommission. **This works now because the cluster has 5 reachable brokers** (the 2 new us-east1 + 1 us-east4 + 2 us-west1) so RF=5 re-replication is possible — the same precondition that step 3's capacity injection unblocked. Watch the eviction:

```bash
for i in $(seq 1 10); do
  echo "--- $(date +%T) ---"
  kubectl --context rp-east -n redpanda exec sts/redpanda-rp-east -c redpanda -- \
    rpk redpanda admin brokers list | awk 'NR>1 {print $1, $4, $6, $7}'
  sleep 30
done
```

Expected — brokers 5 and 6 transition `active false → draining false → (gone)`, and final state is the original 2 / 2 / 1 layout with new IDs:

```
2 us-east4  active true     # the original eu broker, untouched
3 us-west1  active true
4 us-west1  active true
7 us-east1  active true     # newly-joined replacements for the lost brokers 0, 1
8 us-east1  active true
```

You can fall back to **manual decommission** (`rpk redpanda admin brokers decommission 5; rpk redpanda admin brokers decommission 6`) before tearing down the infrastructure if you want to drain replicas off the failover brokers *while they're still reachable* — useful for clean operational handoffs (e.g. you're keeping rp-failover provisioned but reverting the cluster to 3-region). Auto-decommission is the simpler default for the "rp-east is back, throw away the temporary capacity" case shown above.

**Final cleanup:** revert the four-cluster `multicluster.peers` lists back to three in each surviving cluster's helm values and `helm upgrade` so rp-east, rp-west, rp-eu stop trying to reach the deleted peer. The cluster ends at the original 2 / 2 / 1 layout — 2 brokers in us-east1 (new IDs 7, 8), 2 in us-west1 (3, 4), 1 in us-east4 (2). Quorum properties and rack-leader preferences are restored.

**Important caveats observed during validation:**

- **Auto-decom requires the autobalancer to have a healthy view of the cluster.** With `RF=N` (where N is the broker count), losing any broker leaves no spare capacity — the autobalancer can't move replicas off a "ghost" broker because there's nowhere for them to land. The capacity-injection step is *required*; you cannot get back to `Healthy: true` without it. If you choose `RF < broker count` (e.g. `RF=3` over a 5-broker cluster) the autobalancer will self-heal a single broker loss without intervention.
- **The operator reverts cluster config from the StretchCluster spec on every reconcile.** Any `rpk cluster config set` against keys that are also in `spec.config.cluster` will be undone on the next reconcile pass. If you want a different timeout for a one-off demo, edit `<cloud>/manifests/stretchcluster.yaml` and re-apply rather than setting it via rpk.
- **Cross-region heartbeats and the hardcoded 100 ms `node_status_rpc` timeout.** Inter-continental region pairs (e.g. `europe-west1 ↔ us-east1`, RTT ~100 ms) will *appear* unavailable to the controller during heartbeat hiccups, which can trigger an unwanted decommission cascade. Pick region triples whose worst-case pairwise RTT stays under ~70 ms (see [Cost (running)](#cost-running) for a GCP example using `us-east1 / us-west1 / us-east4`).

After the demo, confirm the cluster is healthy (`Healthy=True`, `0` under-replicated partitions) and that the `multicluster.peers`/raft layer is intact via `rpk k8s multicluster status`.

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
cd <aws|gcp|azure>/terraform
terraform destroy
# (GCP: terraform destroy -var project_id=<your-gcp-project>)

# 4. Remove the now-stale kubectl contexts/clusters/users from your local kubeconfig.
#    Skip this and the next `terraform apply` will fail to register fresh
#    contexts with "the context 'rp-east' already exists" (the rename step
#    in `kubectl_setup_commands` errors when the alias is taken).
#
#    Note: `kubectl config rename-context` only renames the *context*; the
#    underlying cluster + user records keep the cloud's full name (GCP
#    `gke_<project>_<region>_rp-east`, AWS `arn:aws:eks:...:cluster/rp-east`,
#    Azure `rp-east`). Match by name suffix to catch all three.
for C in rp-east rp-west rp-eu; do
  kubectl config delete-context "$C" 2>/dev/null || true
done
for NAME in $(kubectl config view -o jsonpath='{.clusters[*].name}' | tr ' ' '\n' | grep -E 'rp-(east|west|eu)$'); do
  kubectl config delete-cluster "$NAME" 2>/dev/null || true
done
for NAME in $(kubectl config view -o jsonpath='{.users[*].name}' | tr ' ' '\n' | grep -E 'rp-(east|west|eu)$'); do
  kubectl config delete-user "$NAME" 2>/dev/null || true
done
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

### 3. Operator pods crashloop after install with "duplicate peer name" / raft can't form

Symptom: bootstrap output shows all peers with `name: redpanda-operator` (or whatever you passed to `--name-override`). The chart renders `--peer=<same>://addr1 --peer=<same>://addr2 --peer=<same>://addr3` and raft can't disambiguate. Fix: drop `--name-override` and use **per-cluster helm release names equal to the context name** plus `fullnameOverride: <ctx>` in values. The cluster.Name then carries the context name (unique) and the cert Secret name (`<ctx>-multicluster-certificates`) lines up with what the chart looks for via `operator.Fullname`.

### 4. helm install fails: "apiServerExternalAddress must be specified in multicluster mode"

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

### 5. Broker pods stuck `Init:0/3` with "MountVolume.SetUp failed for volume redpanda-default-cert: secret not found"

The operator created `redpanda-default-root-certificate` (CA) and the cert-manager `Certificate`/`Issuer` resources, but cert-manager itself isn't installed, so the leaf cert Secrets `redpanda-default-cert` and `redpanda-external-cert` never exist. Install cert-manager (step 5 above), then either wait or force-replace the stuck pods (`kubectl delete pod redpanda-<pool>-0 --grace-period=0 --force`) so kubelet retries the mount.

### 6. Brokers running but never become Ready (cluster_discovery loop)

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

### 7. `flat` mode set but per-pool Services for remote pools don't exist

Symptom: `kubectl get svc -n redpanda` in `rp-east` shows only `redpanda-rp-east-0`, not `redpanda-rp-west-0` or `redpanda-rp-eu-0`. The operator skips rendering for remote pools when `services.perPod.remote.enabled: false`. Set it to `true` in every NodePool.

### 8. StretchCluster `ResourcesSynced=False`: "spec.clusterIPs[0]: Invalid value: ['None']: may not change once set"

Upgrade-only. The operator wants to convert per-pod Services to headless (clusterIP=None) for flat mode, but K8s doesn't allow changing `spec.clusterIP` after creation, so this only triggers when migrating an existing deploy from non-flat to flat (fresh deploys from this repo's manifests come up headless on first reconcile and never hit it). Delete the affected Services (`kubectl delete svc redpanda-rp-{east,west,eu}-0 -n redpanda` on every cluster); the operator immediately recreates them headless on the next reconcile.

### 9. `rpk topic create` from inside a broker pod hangs / "i/o timeout" on port 9093

Kafka client port `9093` (and Pandaproxy `8082`, Admin `9644`) are not open across cluster CIDRs in firewall/NSG rules by default — many setup guides only mention the broker RPC port `33145`. The Terraform in this repo opens all five via the `cross_cluster_ports` variable on every cloud (see `aws/terraform/sg.tf`, `gcp/terraform/firewall.tf`, `azure/terraform/nsg.tf`).

### 10. PVC `Pending`: "0/3 nodes are available: pod has unbound immediate PersistentVolumeClaims"

Cluster has no default StorageClass. Cloud-specific defaults:
- **AWS / EKS**: newer EKS doesn't ship `gp2` annotated default — `aws/terraform/eks.tf` patches `gp2` as default automatically.
- **GCP / GKE**: `standard-rwo` is default out of the box.
- **Azure / AKS**: `default` (Azure Managed Disks) is default out of the box.

If the PVC was created **before** the default class annotation existed, delete the stuck PVC and pod so they get recreated picking up the new default:
```bash
kubectl --context <c> -n redpanda delete pvc datadir-redpanda-<pool>-0
kubectl --context <c> -n redpanda delete pod redpanda-<pool>-0 --grace-period=0 --force
```

## Cost (running)

- **AWS**: 3× EKS control plane + 9× m5.xlarge + 3× internal NLB + TGW (3 attachments + 3 inter-region peerings) ≈ **$2.10/hr** at on-demand pricing, plus inter-region data transfer.
- **GCP**: 3× regional GKE control plane @ $0.10/hr ($0.30/hr) + 27× n2-standard-4 @ $0.1942/hr ($5.24/hr — regional clusters spread `node_count=3` across 3 zones, so 9 VMs per cluster × 3 clusters) + 27× 50 GB pd-balanced boot disks ($0.18/hr) + 3× internal Passthrough Network LB forwarding rules @ $0.025/hr ($0.075/hr) + 3× Cloud NAT gateway @ $0.045/hr ($0.135/hr) + Cloud Router (free) ≈ **$5.93/hr** at on-demand pricing, plus inter-region egress (charged per GB).
- **Azure**: 3× AKS control plane (free with paid SKU) + 9× Standard_D4s_v5 (~$0.19/hr each) + 3× internal Standard LB ≈ **~$1.80/hr**, plus VNet peering + cross-region transfer.

Tear down promptly when validation is done.
