#!/usr/bin/env bash
# aws/scripts/teardown.sh — tear down the AWS stretch-cluster stack cleanly.
#
# Handles the failure modes a naive `terraform destroy` hits:
#   - NodePool / StretchCluster CR finalizers held by a now-gone operator
#   - Peer Service finalizers held by a now-gone AWS LBC
#   - Orphan NLBs / k8s-* security groups blocking VPC delete
#   - "available" ENIs blocking subnet delete
#   - kubernetes_namespace / helm_release timeouts on a destroyed EKS API
#     server (`context deadline exceeded`)
#
# Usage:
#   ./teardown.sh                  # main stack only (rp-east, rp-west, rp-eu)
#   ./teardown.sh --with-failover  # also tear down aws/terraform-failover
#
# Idempotent — safe to re-run after a partial failure.

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TF_MAIN=$SCRIPT_DIR/../terraform
TF_FAILOVER=$SCRIPT_DIR/../terraform-failover

CONTEXTS=(rp-east rp-west rp-eu)
FAILOVER_CTX=rp-failover
MAIN_REGIONS=(us-east-1 us-west-2 eu-west-1)
FAILOVER_REGION=us-east-2

INCLUDE_FAILOVER=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --with-failover) INCLUDE_FAILOVER=1; shift ;;
    -h|--help) sed -n '2,/^# Idempotent/p' "$0" | sed 's/^# *//;s/^#$//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

log() { echo "[teardown] $*" >&2; }

# Delete peer Services so AWS LBC cleans up its NLBs while still alive.
delete_peer_services() {
  local ctx=$1
  kubectl --context "$ctx" -n redpanda get svc -o name 2>/dev/null \
    | grep -E 'multicluster-peer$' \
    | xargs -r kubectl --context "$ctx" -n redpanda delete --wait=false --ignore-not-found 2>/dev/null \
    | sed "s/^/  $ctx: /" || true
}

# Clear finalizers on the operator's CRs so the namespace can finalize even
# after we uninstall the operator.
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
  helm --kube-context "$ctx" uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true
}

# Force-strip namespace finalizers via the /finalize subresource. Unblocks
# stuck Terminating namespaces when the controllers that own the finalizers
# are already gone.
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

# Wait briefly for AWS LBC to drain its NLBs after we deleted the Services.
wait_for_nlbs_gone() {
  log "waiting up to 90s for LBC to drain NLBs..."
  local deadline=$(($(date +%s) + 90))
  while [[ $(date +%s) -lt $deadline ]]; do
    local count=0
    for r in "${MAIN_REGIONS[@]}" "$FAILOVER_REGION"; do
      n=$(aws elbv2 describe-load-balancers --region $r \
        --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-redpanda`) || contains(LoadBalancerName, `k8s-rpfailov`)] | length(@)' \
        --output text 2>/dev/null)
      count=$((count + ${n:-0}))
    done
    [[ $count -eq 0 ]] && return 0
    sleep 5
  done
  log "  some NLBs still present — sweep step will force-delete"
}

# Pre-empt TF k8s/helm provider hangs by removing them from state. With the
# EKS cluster gone, TF can't talk to the API server; without these removed
# from state, `terraform destroy` hits `context deadline exceeded` for tens
# of minutes per resource.
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
  terraform destroy -auto-approve 2>&1 | tail -5 | sed 's/^/  /'
  popd >/dev/null
}

# Sweep AWS resources the LBC / EKS leave behind that block VPC delete.
aws_sweep() {
  for r in "$@"; do
    log "$r: sweep orphan NLBs"
    for arn in $(aws elbv2 describe-load-balancers --region $r \
      --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-redpanda`) || contains(LoadBalancerName, `k8s-rpfailov`) || contains(LoadBalancerName, `k8s-traffic`)].LoadBalancerArn' \
      --output text 2>/dev/null); do
      aws elbv2 delete-load-balancer --region $r --load-balancer-arn "$arn" 2>/dev/null \
        && log "  deleted nlb: $arn" || true
    done
    log "$r: sweep orphan k8s-* security groups"
    for sg in $(aws ec2 describe-security-groups --region $r \
      --filters 'Name=group-name,Values=k8s-redpanda*,k8s-traffic*,k8s-rpfailov*' \
      --query 'SecurityGroups[].GroupId' --output text 2>/dev/null); do
      # Strip rules first to break circular references.
      perms=$(aws ec2 describe-security-groups --region $r --group-ids $sg \
        --query 'SecurityGroups[0].IpPermissions' --output json 2>/dev/null)
      [[ "$perms" != "[]" && -n "$perms" ]] && \
        aws ec2 revoke-security-group-ingress --region $r --group-id $sg \
          --ip-permissions "$perms" >/dev/null 2>&1 || true
      pe=$(aws ec2 describe-security-groups --region $r --group-ids $sg \
        --query 'SecurityGroups[0].IpPermissionsEgress' --output json 2>/dev/null)
      [[ "$pe" != "[]" && -n "$pe" ]] && \
        aws ec2 revoke-security-group-egress --region $r --group-id $sg \
          --ip-permissions "$pe" >/dev/null 2>&1 || true
      aws ec2 delete-security-group --region $r --group-id $sg 2>/dev/null \
        && log "  deleted sg: $sg" || true
    done
    log "$r: sweep available ENIs (ELB/EKS-tagged)"
    for eni in $(aws ec2 describe-network-interfaces --region $r \
      --filters 'Name=status,Values=available' \
      --query 'NetworkInterfaces[?contains(Description, `ELB`) || contains(Description, `EKS`)].NetworkInterfaceId' \
      --output text 2>/dev/null); do
      aws ec2 delete-network-interface --region $r --network-interface-id $eni 2>/dev/null \
        && log "  deleted eni: $eni" || true
    done
  done
}

# Remove rp-* contexts/clusters/users from kubeconfig — but only the
# AWS-backed ones. We resolve each rp-* context's underlying cluster and
# only act on it if the cluster name is the EKS ARN form (`arn:aws:eks:…`).
# This keeps GCP/Azure contexts with the same alias names (e.g. when the
# user has been validating multiple clouds back-to-back) intact.
clean_kubectl() {
  local pattern=$1
  for ctx in $(kubectl config view -o jsonpath='{.contexts[*].name}' 2>/dev/null \
                 | tr ' ' '\n' | grep -E "$pattern"); do
    local cluster
    cluster=$(kubectl config view -o jsonpath="{.contexts[?(@.name==\"$ctx\")].context.cluster}" 2>/dev/null)
    if [[ "$cluster" == arn:aws:eks:* ]]; then
      kubectl config delete-context "$ctx" 2>/dev/null && log "  deleted context $ctx"   || true
      kubectl config delete-cluster "$cluster" 2>/dev/null && log "  deleted cluster $cluster" || true
      kubectl config delete-user    "$cluster" 2>/dev/null && log "  deleted user    $cluster" || true
    else
      log "  skipping $ctx (cluster=$cluster — not AWS EKS)"
    fi
  done
}

###################
# Main flow
###################

# If tearing down both stacks, do failover first so its TGW peering
# attachments are detached before we destroy the main stack's TGWs.
if [[ $INCLUDE_FAILOVER -eq 1 ]]; then
  log "=== failover stack ==="
  delete_peer_services "$FAILOVER_CTX"
  patch_finalizers "$FAILOVER_CTX"
  helm_uninstall_all "$FAILOVER_CTX"
  force_finalize_ns "$FAILOVER_CTX"
fi

log "=== main stack k8s pre-cleanup ==="
for ctx in "${CONTEXTS[@]}"; do delete_peer_services "$ctx"; done
for ctx in "${CONTEXTS[@]}"; do patch_finalizers   "$ctx"; done
for ctx in "${CONTEXTS[@]}"; do helm_uninstall_all "$ctx"; done
for ctx in "${CONTEXTS[@]}"; do force_finalize_ns  "$ctx"; done

wait_for_nlbs_gone

if [[ $INCLUDE_FAILOVER -eq 1 ]]; then
  tf_state_rm_k8s "$TF_FAILOVER"
  tf_destroy      "$TF_FAILOVER"
fi
tf_state_rm_k8s "$TF_MAIN"
tf_destroy      "$TF_MAIN"

log "=== post-destroy sweep ==="
aws_sweep "${MAIN_REGIONS[@]}"
[[ $INCLUDE_FAILOVER -eq 1 ]] && aws_sweep "$FAILOVER_REGION"

# Final destroy pass picks up anything the sweep unblocked (typically the
# VPC, once its dangling SGs / ENIs are gone).
log "=== final terraform destroy pass ==="
[[ $INCLUDE_FAILOVER -eq 1 ]] && tf_destroy "$TF_FAILOVER"
tf_destroy "$TF_MAIN"

log "=== kubectl cleanup ==="
clean_kubectl 'rp-(east|west|eu|failover)$'

log "done"
