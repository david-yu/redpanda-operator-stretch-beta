#!/usr/bin/env bash
# azure/scripts/teardown.sh — tear down the Azure stretch-cluster stack cleanly.
#
# Handles the failure modes a naive `terraform destroy` hits:
#   - NodePool / StretchCluster CR finalizers held by a now-gone operator
#   - Peer Service finalizers held by the AKS cloud-controller-manager once
#     the cluster is being destroyed
#   - Orphan internal Standard Load Balancers in the AKS-managed `MC_*`
#     resource groups (left behind when the cloud-controller-manager doesn't
#     clean up before AKS itself is deleted — rare but not unheard of)
#   - kubernetes_namespace / helm_release timeouts on a destroyed AKS API
#     server (`context deadline exceeded`)
#   - The kubernetes_service "Unexpected Identity Change" provider quirk we
#     hit during validation; recovered by a state-rm + retry pattern
#
# Usage:
#   ./teardown.sh                  # main stack only (rp-east, rp-west, rp-eu)
#   ./teardown.sh --with-failover  # also tear down azure/terraform-failover
#
# Idempotent — safe to re-run after a partial failure.

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TF_MAIN=$SCRIPT_DIR/../terraform
TF_FAILOVER=$SCRIPT_DIR/../terraform-failover

CONTEXTS=(rp-east rp-west rp-eu)
FAILOVER_CTX=rp-failover

INCLUDE_FAILOVER=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --with-failover) INCLUDE_FAILOVER=1; shift ;;
    -h|--help) sed -n '2,/^# Idempotent/p' "$0" | sed 's/^# *//;s/^#$//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

log() { echo "[teardown] $*" >&2; }

# Delete peer Services so the AKS cloud-controller-manager can drop the
# internal load balancer it provisioned for them while still alive.
delete_peer_services() {
  local ctx=$1
  kubectl --context "$ctx" -n redpanda get svc -o name 2>/dev/null \
    | grep -E 'multicluster-peer$' \
    | xargs -r kubectl --context "$ctx" -n redpanda delete --wait=false --ignore-not-found 2>/dev/null \
    | sed "s/^/  $ctx: /" || true
}

patch_finalizers() {
  local ctx=$1
  for r in $(kubectl --context "$ctx" -n redpanda get nodepool,stretchcluster -o name 2>/dev/null); do
    kubectl --context "$ctx" -n redpanda patch "$r" --type=merge \
      -p '{"metadata":{"finalizers":[]}}' 2>/dev/null \
      | sed "s/^/  $ctx: /" || true
  done
}

helm_uninstall_all() {
  local ctx=$1
  helm --kube-context "$ctx" uninstall redpanda -n redpanda 2>/dev/null || true
  helm --kube-context "$ctx" uninstall "$ctx" -n redpanda 2>/dev/null || true
  helm --kube-context "$ctx" uninstall redpanda-operator -n redpanda 2>/dev/null || true
  helm --kube-context "$ctx" uninstall cert-manager -n cert-manager 2>/dev/null || true
}

force_finalize_ns() {
  local ctx=$1
  local ns=${2:-redpanda}
  kubectl --context "$ctx" get ns "$ns" 2>/dev/null | grep -q Terminating || return 0
  log "$ctx: ns/$ns stuck Terminating — force-finalizing"
  local port=$((RANDOM % 1000 + 18000))
  kubectl --context "$ctx" proxy --port=$port >/dev/null 2>&1 &
  local pid=$!
  sleep 2
  curl -sX PUT -H 'Content-Type: application/json' \
    --data-binary "{\"apiVersion\":\"v1\",\"kind\":\"Namespace\",\"metadata\":{\"name\":\"$ns\"},\"spec\":{\"finalizers\":[]}}" \
    "http://localhost:$port/api/v1/namespaces/$ns/finalize" >/dev/null 2>&1 || true
  kill $pid 2>/dev/null
  wait 2>/dev/null
}

tf_state_rm_k8s() {
  local dir=$1
  log "$dir: pruning kubernetes/helm resources from state"
  pushd "$dir" >/dev/null
  for r in $(terraform state list 2>/dev/null | grep -E '^(kubernetes_|helm_release\.)'); do
    terraform state rm "$r" 2>/dev/null | sed 's/^/  /' || true
  done
  popd >/dev/null
}

# `terraform destroy` with retry — handles the kubernetes_service
# "Unexpected Identity Change" provider quirk by removing the offender
# from state and trying once more.
tf_destroy() {
  local dir=$1
  log "$dir: terraform destroy"
  pushd "$dir" >/dev/null
  local out
  out=$(terraform destroy -auto-approve 2>&1) || true
  if echo "$out" | grep -q 'Unexpected Identity Change'; then
    log "  hit Unexpected Identity Change — pruning offender from state and retrying"
    for r in $(terraform state list 2>/dev/null | grep -E '^kubernetes_'); do
      terraform state rm "$r" >/dev/null 2>&1 || true
    done
    out=$(terraform destroy -auto-approve 2>&1) || true
  fi
  echo "$out" | tail -5 | sed 's/^/  /'
  popd >/dev/null
}

# Sweep orphan internal LBs from MC_* resource groups (the AKS-managed RGs
# that hold cluster node + LB resources). If the cloud-controller-manager
# didn't clean up before AKS was deleted, the LB sits in MC_* and blocks RG
# delete.
azure_sweep() {
  log "sweeping orphan LBs in MC_* resource groups"
  for rg in $(az group list --query "[?starts_with(name, 'MC_')].name" -o tsv 2>/dev/null); do
    for lb in $(az network lb list -g "$rg" --query '[].name' -o tsv 2>/dev/null); do
      az network lb delete -g "$rg" -n "$lb" --no-wait 2>/dev/null \
        && log "  deleted lb: $rg/$lb" || true
    done
  done
}

# Remove rp-* contexts/clusters/users from kubeconfig — but only those
# resolving to AKS clusters in this account. Matching only on the alias
# would also blow away the user's AWS/GCP contexts when they happen to
# share the same alias (the script in this repo's other clouds does the
# same check).
clean_kubectl() {
  local pattern=$1
  for ctx in $(kubectl config view -o jsonpath='{.contexts[*].name}' 2>/dev/null \
                 | tr ' ' '\n' | grep -E "$pattern"); do
    local cluster user
    cluster=$(kubectl config view -o jsonpath="{.contexts[?(@.name==\"$ctx\")].context.cluster}" 2>/dev/null)
    user=$(kubectl config view -o jsonpath="{.contexts[?(@.name==\"$ctx\")].context.user}" 2>/dev/null)
    # AKS users are named clusterUser_<rg>_<cluster>; AKS cluster entries are
    # just the cluster name. Use the user prefix as the unambiguous AKS marker.
    if [[ "$user" == clusterUser_* ]]; then
      kubectl config delete-context "$ctx" 2>/dev/null     && log "  deleted context $ctx"   || true
      kubectl config delete-cluster "$cluster" 2>/dev/null && log "  deleted cluster $cluster" || true
      kubectl config delete-user    "$user" 2>/dev/null    && log "  deleted user    $user"    || true
    else
      log "  skipping $ctx (user=$user — not AKS)"
    fi
  done
}

###################
# Main flow
###################

# Failover first so its VNet peerings drop before we destroy the main VNets.
if [[ $INCLUDE_FAILOVER -eq 1 ]]; then
  log "=== failover stack ==="
  delete_peer_services "$FAILOVER_CTX"
  patch_finalizers     "$FAILOVER_CTX"
  helm_uninstall_all   "$FAILOVER_CTX"
  force_finalize_ns    "$FAILOVER_CTX"
fi

log "=== main stack k8s pre-cleanup ==="
for ctx in "${CONTEXTS[@]}"; do delete_peer_services "$ctx"; done
for ctx in "${CONTEXTS[@]}"; do patch_finalizers     "$ctx"; done
for ctx in "${CONTEXTS[@]}"; do helm_uninstall_all   "$ctx"; done
for ctx in "${CONTEXTS[@]}"; do force_finalize_ns    "$ctx"; done

if [[ $INCLUDE_FAILOVER -eq 1 ]]; then
  tf_state_rm_k8s "$TF_FAILOVER"
  tf_destroy      "$TF_FAILOVER"
fi
tf_state_rm_k8s "$TF_MAIN"
tf_destroy      "$TF_MAIN"

log "=== post-destroy sweep ==="
azure_sweep

# Final destroy pass picks up anything the sweep unblocked.
log "=== final terraform destroy pass ==="
[[ $INCLUDE_FAILOVER -eq 1 ]] && tf_destroy "$TF_FAILOVER"
tf_destroy "$TF_MAIN"

log "=== kubectl cleanup ==="
clean_kubectl 'rp-(east|west|eu|failover)$'

log "done"
