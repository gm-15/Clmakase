# Load Test Evidence — 2026-02-26

> Final 150,000-VU load test for the OliveYoung flash-sale defense system.
> Verified via Datadog `as_rate()` over a 20-minute test window.

## Test Metadata

| Field | Value |
|---|---|
| Date | 2026-02-26 (KST) |
| Window | 11:54 am – 12:14 pm (20 min) |
| Test tool | k6 distributed |
| Parallelism | 10 (15,000 VU per pod, 8 core / 16 GB) |
| Scenario | 0 → 150,000 VU over 2-min ramp-up → 13-min peak hold → 5-min ramp-down |
| Datadog query | `sum:trace.servlet.request.hits{service:oliveyoung-api}.as_rate().rollup(max, 1)` |
| Service tag | `service:oliveyoung-api` |

## Verified Metrics

| Metric | Value | Source |
|---|---|---|
| Peak RPS | **56,300 hits/s** | Datadog MAX (datadog-rps-overview.png) |
| Average over window | **38,500 hits/s** | Datadog AVG (includes ramp-up/down) |
| Stable peak-window RPS | **49,500 hits/s** | Self-reported sustained average during peak hold |
| Total requests | **4.65M hits** | Datadog SUM |
| Success rate | **100%** (zero 5xx errors) | Datadog error tag analysis |
| P99 latency | **≤180 ms** | Datadog APM |
| OOMKilled | **0** | k8s event log |
| CrashLoopBackOff | **0** | k8s event log |
| Service interruption | **none** | Datadog uptime |
| Max API pods | **100** (KEDA maxReplicas) | k8s metrics |
| Max nodes | **26** Spot instances (~128 vCPU / ~600 GB) | Karpenter event log |

## Files

| File | Description |
|---|---|
| `datadog-rps-overview.png` | Datadog RPS-over-time screenshot for the 20-minute window |
| `load-test-report.pdf` | Load-test-only summary report (CloudWave portfolio) |
| `full-cicd-load-report.pdf` | Combined CI/CD + load-test portfolio report |
| `monitoring-summary.pdf` | Datadog dashboard configuration & monitoring stack |

## Improvement Journey (1st → 3rd test)

| Item | 1st & 2nd | 3rd (final) |
|---|---|---|
| OOMKilled | many | 0 |
| Initial pods | 2 | 10 (warm-up) |
| KEDA scaleUp speed | 10/30s | 50/30s |
| istio-proxy memory limit | 256 Mi → 2 Gi (still OOM) | 10 Gi (request/limit separated) |
| Deployment replicas field | hardcoded 2 | removed (KEDA-only control) |

## Engineering Reflection — Expected vs Actual RPS

The 150 K VU theoretical peak was ~112 K RPS; the measured peak was 56.3 K. Two factors compounded:

1. **Iteration period stretch** — under heavy load, server response time grew, which extended the k6 VU iteration period from ~10 s to ~20 s+. Throughput per VU halved in steady state.
2. **Sidecar overhead** — every request traverses an Istio sidecar; the proxy's networking cost throttled aggregate throughput.

The conclusion is that 56 K RPS was achieved with **zero error budget consumed**, on **all-Spot instances**, with **60-second responsiveness** to load via KEDA + Karpenter.

## Companion Data

CSV files from earlier comparison runs (Version A vs Version C, 2026-02-19 ~ 02-20) are at the repo root:
- `load-test-result-version-a-*.csv`
- `load-test-result-version-c-*.csv`
- `load-test-compare.ps1` (PowerShell harness)
- `k6-summary.json` (intermediate run, lower-VU smoke test)
