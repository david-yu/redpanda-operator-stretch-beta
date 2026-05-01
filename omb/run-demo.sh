#!/usr/bin/env bash
# omb/run-demo.sh — automate the cordon-and-delete regional-failure step
# for Demo A or Demo B while OMB Jobs pump 10 Mbps in the background.
#
# Usage:
#   ./omb/run-demo.sh demo-a            # Demo A: cordon rp-east, wait, uncordon
#   ./omb/run-demo.sh demo-b-fail       # Demo B step 1: cordon rp-east, leave it down
#   ./omb/run-demo.sh demo-b-restore    # Demo B step 6: uncordon rp-east
#
# Assumes:
#   - kubectl contexts rp-east, rp-west, rp-eu (and rp-failover for Demo B step 4) registered
#   - StretchCluster healthy (steps 1-9 of root README done)
#   - OMB Jobs already running (`kubectl apply -f omb/producer-job.yaml -f omb/consumer-job.yaml`)
#
# The script prints periodic broker / OMB-throughput snapshots so the
# demo's "did the cluster keep producing" question is answerable from the
# transcript alone — no need to keep multiple kubectl logs windows open.

set -uo pipefail

CTX_PRIMARY=${CTX_PRIMARY:-rp-east}
CTX_OBSERVER=${CTX_OBSERVER:-rp-west}
NS=${NS:-redpanda}

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

snapshot() {
  log "=== brokers (from $CTX_OBSERVER's controller view) ==="
  kubectl --context "$CTX_OBSERVER" -n "$NS" exec sts/redpanda-${CTX_OBSERVER} -c redpanda -- \
    rpk cluster health 2>&1 | grep -E "^Healthy|Nodes down|Under-replicated|Leaderless" | sed 's/^/  /'
  log "=== producer throughput (last 5 lines) ==="
  kubectl --context "$CTX_PRIMARY" -n "$NS" logs job/omb-producer --tail 5 2>/dev/null \
    | grep -E "records sent|error" | sed 's/^/  /' || echo "  (producer logs unavailable)"
  log "=== consumer-group lag ==="
  kubectl --context "$CTX_OBSERVER" -n "$NS" exec sts/redpanda-${CTX_OBSERVER} -c redpanda -- \
    rpk group describe omb-consumer 2>&1 | grep -E "STATE|TOTAL-LAG|MEMBERS" | head -5 | sed 's/^/  /'
  echo
}

cordon_primary() {
  log "cordon all $CTX_PRIMARY nodes"
  for n in $(kubectl --context "$CTX_PRIMARY" get nodes -o name); do
    kubectl --context "$CTX_PRIMARY" cordon "$n" >/dev/null
  done
  log "delete $CTX_PRIMARY broker pods (so they sit Pending on cordoned nodes)"
  kubectl --context "$CTX_PRIMARY" -n "$NS" delete pod -l app.kubernetes.io/component=redpanda-statefulset \
    --grace-period=10 --wait=false 2>/dev/null \
    | sed 's/^/  /'
  # Fallback: the label selector above is operator-version-dependent.
  # Try a name match if the selector matched nothing.
  if ! kubectl --context "$CTX_PRIMARY" -n "$NS" get pod -l app.kubernetes.io/component=redpanda-statefulset 2>/dev/null | grep -q "redpanda-${CTX_PRIMARY}"; then
    kubectl --context "$CTX_PRIMARY" -n "$NS" delete pod \
      "redpanda-${CTX_PRIMARY}-0" "redpanda-${CTX_PRIMARY}-1" \
      --grace-period=10 --wait=false --ignore-not-found 2>/dev/null \
      | sed 's/^/  /'
  fi
}

uncordon_primary() {
  log "uncordon all $CTX_PRIMARY nodes"
  for n in $(kubectl --context "$CTX_PRIMARY" get nodes -o name); do
    kubectl --context "$CTX_PRIMARY" uncordon "$n" >/dev/null
  done
}

case ${1:-} in
  demo-a)
    log "Demo A: cordon → observe → uncordon"
    snapshot
    cordon_primary
    log "wait 120s for leaders to relocate"
    sleep 120
    snapshot
    uncordon_primary
    log "wait 90s for brokers to come back + leaders to migrate home"
    sleep 90
    snapshot
    log "Demo A complete"
    ;;
  demo-b-fail)
    log "Demo B step 1: cordon $CTX_PRIMARY (will stay down — run demo-b-restore later)"
    snapshot
    cordon_primary
    log "wait 60s for initial broker-down state"
    sleep 60
    snapshot
    log "step 1 done — waiting for autobalancer-stalled state is up to you (~10-15 min)"
    ;;
  demo-b-restore)
    log "Demo B step 6: uncordon $CTX_PRIMARY"
    uncordon_primary
    log "wait 90s for brokers to schedule + rejoin"
    sleep 90
    snapshot
    log "step 6 done"
    ;;
  *)
    echo "usage: $0 {demo-a|demo-b-fail|demo-b-restore}" >&2
    exit 2
    ;;
esac
