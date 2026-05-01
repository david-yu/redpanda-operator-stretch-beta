#!/usr/bin/env bash
# gcp/scripts/teardown.sh — tear down the GCP stretch-cluster stack cleanly.
#
# GCP destroys are usually clean — there's no per-cluster LB controller
# adding orphan resources the way AWS LBC does, and the global VPC + GKE
# integrations clean up after themselves. The two failure modes worth
# handling here are the same as on every cloud:
#
#   - NodePool / StretchCluster CR finalizers held by a now-gone operator
#     blocking namespace finalize
#   - kubernetes_namespace / helm_release timeouts on a destroyed GKE API
#     server (`context deadline exceeded`)
#
# Usage:
#   ./teardown.sh --project <id>                  # main stack only
#   ./teardown.sh --project <id> --with-failover  # also gcp/terraform-failover
#
# Idempotent — safe to re-run after a partial failure.

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TF_MAIN=$SCRIPT_DIR/../terraform
TF_FAILOVER=$SCRIPT_DIR/../terraform-failover

CONTEXTS=(rp-east rp-west rp-eu)
FAILOVER_CTX=rp-failover

PROJECT_ID=""
INCLUDE_FAILOVER=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --project) PROJECT_ID=$2; shift 2 ;;
    --with-failover) INCLUDE_FAILOVER=1; shift ;;
    -h|--help) sed -n '2,/^# Idempotent/p' "$0" | sed 's/^# *//;s/^#$//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$PROJECT_ID" ]]; then
  echo "error: --project <id> is required (must match the main stack's var.project_id)" >&2
  exit 2
fi

log() { echo "[teardown] $*" >&2; }

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

tf_destroy() {
  local dir=$1
  log "$dir: terraform destroy"
  pushd "$dir" >/dev/null
  terraform destroy -auto-approve -var "project_id=$PROJECT_ID" 2>&1 | tail -5 | sed 's/^/  /'
  popd >/dev/null
}

# Remove rp-* contexts/clusters/users from kubeconfig — but only those that
# resolve to this project's GKE clusters. Matching only on the alias name
# (rp-east etc.) would also blow away the user's AWS/Azure contexts when
# they happen to share the same alias.
clean_kubectl() {
  local pattern=$1
  local cluster_pattern="^gke_${PROJECT_ID}_.*_rp-(east|west|eu|failover)$"
  for ctx in $(kubectl config view -o jsonpath='{.contexts[*].name}' 2>/dev/null \
                 | tr ' ' '\n' | grep -E "$pattern"); do
    local cluster
    cluster=$(kubectl config view -o jsonpath="{.contexts[?(@.name==\"$ctx\")].context.cluster}" 2>/dev/null)
    if [[ "$cluster" =~ $cluster_pattern ]]; then
      kubectl config delete-context "$ctx" 2>/dev/null && log "  deleted context $ctx"   || true
      kubectl config delete-cluster "$cluster" 2>/dev/null && log "  deleted cluster $cluster" || true
      kubectl config delete-user    "$cluster" 2>/dev/null && log "  deleted user    $cluster" || true
    else
      log "  skipping $ctx (cluster=$cluster — not GCP project $PROJECT_ID)"
    fi
  done
}

###################
# Main flow
###################

if [[ $INCLUDE_FAILOVER -eq 1 ]]; then
  log "=== failover stack ==="
  patch_finalizers   "$FAILOVER_CTX"
  helm_uninstall_all "$FAILOVER_CTX"
  force_finalize_ns  "$FAILOVER_CTX"
fi

log "=== main stack k8s pre-cleanup ==="
for ctx in "${CONTEXTS[@]}"; do patch_finalizers   "$ctx"; done
for ctx in "${CONTEXTS[@]}"; do helm_uninstall_all "$ctx"; done
for ctx in "${CONTEXTS[@]}"; do force_finalize_ns  "$ctx"; done

if [[ $INCLUDE_FAILOVER -eq 1 ]]; then
  tf_state_rm_k8s "$TF_FAILOVER"
  tf_destroy      "$TF_FAILOVER"
fi
tf_state_rm_k8s "$TF_MAIN"
tf_destroy      "$TF_MAIN"

log "=== kubectl cleanup ==="
clean_kubectl 'rp-(east|west|eu|failover)$'

log "done"
