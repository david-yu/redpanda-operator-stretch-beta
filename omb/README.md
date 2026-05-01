# Continuous load generator (10 Mbps) for the demos

A pair of Kubernetes Jobs that drive **~10 Mbps of producer + consumer traffic** against the StretchCluster while you run Demo A or Demo B. The point is to prove that the cluster keeps serving Kafka traffic uninterrupted through a regional outage / failover capacity injection — i.e. that the demos aren't just changing internal raft state, they're also surviving real client load.

> **Why "OMB" in the directory name but `kafka-*-perf-test.sh` under the hood.** The original ask was [OpenMessaging Benchmark](https://github.com/openmessaging/benchmark) on a separate VM. We deliver the same continuous-load shape using Apache Kafka's bundled perf-test scripts running as a `Job` inside the `redpanda` namespace — that gets rid of cross-VPC routing + VM provisioning + OMB driver-config rendering, and it produces the same per-second throughput / latency telemetry you'd read off OMB. Same intent, much simpler delivery.

## What it does

| Component | Image | What it runs |
|---|---|---|
| `omb-producer` Job | `apache/kafka:3.8.0` | `kafka-producer-perf-test.sh --topic load-test --num-records ∞ --record-size 1024 --throughput 1280` → 1280 msgs/s × 1 KiB ≈ **10.5 Mbps** |
| `omb-consumer` Job | `apache/kafka:3.8.0` | `kafka-consumer-perf-test.sh --topic load-test --messages ∞` → drains the topic at producer rate |

Both Jobs run in the `redpanda` namespace, mount the operator-issued CA via a Kafka client config, and use the cluster's headless `redpanda` Service as the bootstrap server. They print one-line throughput summaries every 5 s so you can `kubectl logs -f` either Job and watch the producer's `records sent` count climb (or stall, if the demo broke things).

## Pre-reqs

- StretchCluster healthy on rp-east (you've completed steps 1-9 in the root README)
- The `load-test` topic created with RF=5 / 12 partitions:

```bash
kubectl --context rp-east -n redpanda exec sts/redpanda-rp-east -c redpanda -- \
  rpk topic create load-test --partitions 12 --replicas 5
```

## Run

The Jobs are intentionally cluster-agnostic — they target the `redpanda` Service in the local namespace, so apply them on whichever cluster you want the load to originate from (we use rp-east since that's the primary, but rp-west or rp-eu work just as well):

```bash
# Start the producer + consumer
kubectl --context rp-east -n redpanda apply -f omb/producer-job.yaml
kubectl --context rp-east -n redpanda apply -f omb/consumer-job.yaml

# Tail throughput from the producer side
kubectl --context rp-east -n redpanda logs -f job/omb-producer

# Tail consumer
kubectl --context rp-east -n redpanda logs -f job/omb-consumer
```

A healthy steady-state run prints lines like:

```
6280 records sent, 1256.0 records/sec (1.23 MB/sec), 8.4 ms avg latency, 95.0 ms max latency
6400 records sent, 1280.0 records/sec (1.25 MB/sec), 7.2 ms avg latency, 21.0 ms max latency
```

During the demo's regional-failure step, expect a brief stall (~5-30 s of zero `records/sec` while leaders re-elect) followed by a return to ~1280 records/sec. If the producer reports `Producer.send error` for more than a minute, that's a real cluster problem — not transient.

## Stop

```bash
kubectl --context rp-east -n redpanda delete -f omb/producer-job.yaml -f omb/consumer-job.yaml
```

## Adjusting the rate

Change `--throughput` in `producer-job.yaml`:

| `--throughput` | Bandwidth (1 KiB records) |
|---|---|
| `128` | ~1 Mbps |
| `1280` | ~10 Mbps (default) |
| `12800` | ~100 Mbps |
| `-1` | unbounded — useful for "what's the cluster's ceiling?" probes |

`--record-size` is in bytes; doubling it halves messages-per-second for the same target throughput.
