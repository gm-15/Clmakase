# Clmakase — OliveYoung Flash-Sale Defense System

> **CloudWave 7th Cohort · Final Project**
> A 150,000-VU concurrent flash-sale event system on AWS EKS, verified end-to-end via a 20-minute Datadog-measured load test.
> Domain: `clmakase.click` · Region: `ap-northeast-2`

🇰🇷 한국어 버전: [README.ko.md](README.ko.md)

---

## ✨ At a Glance

- **Production-grade modern stack on AWS EKS** — Kafka 3-Broker StatefulSet, Karpenter (all-Spot), KEDA composite scaling, ArgoCD GitOps, Istio service mesh, Terraform 16-module IaC, GitLab CI/CD 8-stage pipeline.
- **150,000 VU load test passed** with 0 OOMKilled · 0 5xx errors · P99 ≤ 180 ms · 4.65 M total requests in 20 min, all on Spot instances.
- **Backend-driven trouble-shootings**, 10 of which are documented in this README and reproducible against the codebase — most notably the **Aurora "Too many connections" formula derivation** (`maxReplicas × pool_size ≤ max_connections`) that turned scale-out itself into a DB attack surface.

---

## 🛒 Why This Project Exists (Background)

The project was modelled on **the Olive Young flash-sale event** — a recurring moment when 150,000+ customers attempt to purchase the same limited-quantity products within the same minute, and where every architectural failure mode (DB connection exhaustion, broker outages, cold-start latency, scale-out paradoxes) surfaces simultaneously. The Olive Young event was chosen specifically because:

- It is a **public, recurring, time-bounded** workload — the load curve is reproducible in a test environment with k6.
- It is a **high-stakes correctness scenario** — over-selling a single SKU costs trust; under-serving costs revenue; both must be prevented even during partial infrastructure failure.
- It exercises the full stack — CDN, edge, ALB, EKS, Kafka, Aurora, Redis — under a single coordinated load profile.

The system was designed to defend a 150,000-VU spike with zero 5xx errors, zero OOM events, and broker-failure recovery under 500 ms — verified by a 20-minute Datadog-measured load test on 2026-02-26.

---

## 🎯 Verified Metrics (Datadog, 2026-02-26)

Measured by Datadog `as_rate()` query over a 20-minute window — full evidence in [evidence/load-test-2026-02-26/](evidence/load-test-2026-02-26/).

| Metric | Value | Source |
|---|---|---|
| **Peak RPS** | **56,300 hits/s** | [Datadog screenshot](evidence/load-test-2026-02-26/datadog-rps-overview.png) |
| **Stable RPS** | **49,500 hits/s** (peak-window average) | same |
| **Total requests** | **4.65 M hits** (20 min) | same (Datadog SUM) |
| **Success rate** | **100 %** (zero 5xx errors) | same |
| **P99 latency** | **≤ 180 ms** | Datadog APM |
| **OOMKilled** | **0** | k8s event log |
| **Service interruption** | **none** | Datadog uptime |
| **Max API pods** | **100** (KEDA `maxReplicas`) | k8s metrics |
| **Max nodes** | **26** Spot instances (~128 vCPU / ~600 GB) | Karpenter event log |
| **Broker-failure P95** | **3,137 ms → 436 ms (87 % improvement)** | Version A vs Version C comparison ([CSVs](.)) |
| **Order-data loss under broker failure** | **0** (Non-blocking Retry + DLT) | Version C invariant |

> **Datadog query**: `sum:trace.servlet.request.hits{service:oliveyoung-api}.as_rate().rollup(max, 1)`
> **Test window**: 2026-02-26 11:54 am – 12:14 pm KST

---

## 👤 My Role & Responsibilities

I led the project as the team lead and owned the backend + infrastructure tracks below. Security policy details (WAF rules, KMS key policies, Cloud Custodian forensics) were a teammate's track; I integrated their work via Terraform module composition only.

### Owned (interview-defendable in depth)

- **Backend (Spring Boot)** — order-processing service, Kafka producer/consumer, `@RetryableTopic` + `@DltHandler`, **7 custom Micrometer counters** for stage-level retry observability.
- **The Aurora connection-pool formula** — derived `maxReplicas × pool_size ≤ Aurora_max_connections`, reduced HikariCP `pool_size` from 10 → 5 as the resolution.
- **Kafka 3-Broker StatefulSet** — RF=3, `min.insync.replicas=2`, 20 partitions, Idempotent Producer, Non-blocking Retry topic with 3-stage backoff (1 s → 5 s → 30 s) and DLT.
- **Terraform 16-module IaC architecture** — VPC, EKS, RDS, ElastiCache, ALB controller, ArgoCD, ECR, S3, CloudFront, ACM, Route53, security-groups, secrets, waf, kms, cli (SSM Bastion).
- **Karpenter migration** — full transition from Managed Node Group; resolved a chain of 16 cascading errors during stabilization.
- **KEDA composite scaling** — Kafka consumer-lag trigger + Datadog RPS trigger + Cron warm-up trigger; tuned `maxReplicas=100` and `scaleUp 50 pods / 30 s`.
- **GitLab CI/CD 8-stage pipeline** — `test → build → trivy-scan → update-manifest → deploy-secrets → deploy-frontend → load-test → ArgoCD trigger`. Includes commit-SHA-based image tag rewriting via `sed`, `[skip ci]` infinite-loop prevention, and CloudFront cache auto-invalidation.
- **DevSecOps in CI** — Trivy CVE scanning integration, ECR auto-scan configuration, Renovate dependency-update automation.
- **K8s manifests** — `Deployment` (with `spec.replicas` field intentionally removed for KEDA single-source-of-truth control), KEDA `ScaledObject`, Karpenter `NodePool` and `EC2NodeClass`, Istio sidecar resource tuning (256 Mi → 10 Gi memory limit).
- **150,000-VU final load test** — designed scenario, executed via k6 distributed (`parallelism=10`, 15,000 VU per pod, 8 core / 16 GB), wrote the engineering reflection on expected vs measured RPS divergence.

### Team-led (I composed Terraform modules; I do not claim policy-content authorship)

- WAF rule definitions
- KMS key policies
- Secrets Manager rotation policies
- Cloud Custodian forensics policies (`custodian/iam-forensics.yml`, `custodian/ec2-forensics.yml`)
- Istio mTLS PeerAuthentication policy details

### 🚧 Section To Be Added

- **Teamwork & collaboration** — leadership style, conflict resolution, how the team divided ownership across backend/infra/security tracks. (Drafting in progress.)

---

## 🏛️ System Architecture

### Full Architecture
![Full Architecture](assets/architecture/full-architecture.png)

The full system spans the AWS account from edge security (Route53 → WAF → CloudFront → S3) through a Multi-AZ EKS production VPC, a separated developer-access VPC (Session Manager + Client VPN + CLI Server), an observability plane (CloudWatch · Datadog · Falco · Istio · Prometheus · Loki · Tempo · Grafana), an automated security plane (IAM · KMS · ASM · GuardDuty · Inspector · Access Analyzer · Config · Security Hub · ACM · WAF · Shield), and a regional DR plane (`ap-northeast-2` primary ↔ `ap-northeast-1` secondary with Aurora Replica + ElastiCache Global DB) plus a VPC-flow-log forensics pipeline (VPC Flow Logs → Kinesis Data Streams → Kinesis Data Firehose → S3 → EventBridge → Step Functions → SageMaker → Lambda → Slack).

### Production Plane (User-facing traffic)
![Production Plane](assets/architecture/production-plane.png)

User → Route53 → CloudFront (with S3 static frontend offload) → WAF → Internet Gateway → Ingress ALB → EKS pods (Multi-AZ across two AZs, NAT in each public subnet for egress, ElastiCache + Aurora in private data subnets, Bastion Server for admin access). The orange box across the AZs marks the Kafka 3-Broker StatefulSet boundary.

### Development Plane (Internal access)
![Development Plane](assets/architecture/development-plane.png)

Admin → Session Manager → ECR. Developer → Client VPN → CLI Server (private subnet) → EKS / RDS / ElastiCache. GitLab pushes images to ECR through a VPC Endpoint. Egress through a public-subnet NAT.

### Demo Videos

| Title | Link |
|---|---|
| 🎬 **Load Test Demo** — k6 distributed load test driving the system to 150,000 VU | [youtube.com/watch?v=WcVVNoNMsG8](https://www.youtube.com/watch?v=WcVVNoNMsG8) |
| 🎬 **Frontend Demo** — User-facing flash-sale flow walkthrough | [youtube.com/watch?v=sHEY-YEHfT4](https://www.youtube.com/watch?v=sHEY-YEHfT4) |

<details>
<summary>📐 Text-only architecture (for terminal viewers)</summary>

```
User
 │ HTTPS
 ▼
CloudFront ──────────── S3 (React static hosting)
 │
 ▼
WAF ─── ALB (api.clmakase.click)
            │
            ▼
        EKS Cluster (ap-northeast-2)
          │
          ├─ oliveyoung-api Pod × 1~100
          │   ├─ KEDA ScaledObject
          │   │   ├─ Kafka consumer-lag trigger
          │   │   ├─ Datadog RPS trigger
          │   │   └─ Cron warm-up trigger (sale-open)
          │   └─ Istio sidecar (mTLS)
          │
          ├─ Kafka 3-Broker StatefulSet
          │   └─ Zookeeper (leader election · offset)
          │
          ├─ Karpenter NodePool
          │   └─ c/m/r 6th gen+, all-Spot
          │
          └─ ArgoCD (GitOps · selfHeal · prune)
              │
              ├─ Aurora MySQL (Multi-AZ, HikariCP pool=5)
              └─ ElastiCache Redis (queue state)
```

</details>

---

## 🔧 Tech Stack

| Layer | Technology |
|---|---|
| **Orchestration** | EKS v1.30 + Karpenter v1.0.1 |
| **Messaging** | Kafka 3-Broker StatefulSet + Zookeeper (RF=3, `min.insync=2`, 20 partitions) |
| **Auto-scaling** | KEDA composite trigger (Kafka lag / Datadog RPS / Cron warm-up) |
| **GitOps** | ArgoCD + GitLab CI/CD (8-stage pipeline) |
| **Service mesh** | Istio mTLS + Kiali |
| **Data** | Aurora MySQL (Multi-AZ) + ElastiCache Redis |
| **IaC** | Terraform — 16 modules |
| **Monitoring** | Datadog APM + Prometheus (Kiali-only, 6h retention) |
| **Security (CI)** | Trivy CVE scan + ECR auto-scan + Renovate (Owned) |
| **Security (Network/Data)** | WAF + KMS + Secrets Manager + Cloud Custodian (Team-led) |
| **CDN** | CloudFront + S3 + ACM + Route53 |
| **Backend** | Spring Boot · Java 17 · Micrometer (7 custom counters) |

---

## 🚦 Backend Deep Dives

### 1. The Scale-Out Paradox — Aurora "Too many connections"

During load testing, scaling out pods caused Aurora to fail rather than the bottleneck it was meant to relieve. The defect lived at the application's connection-pool level.

**Diagnosis.** Each Spring Boot pod opens up to `pool_size` connections. With KEDA scaling pods to `maxReplicas=100` and a default `pool_size=10`, the cluster requested up to 1,000 simultaneous DB connections — far past Aurora's `max_connections` budget.

**Formula derivation.**
```
total_db_connections = maxReplicas × HikariCP.pool_size
must hold:  total_db_connections ≤ Aurora.max_connections
```

**Resolution.** Reduced `pool_size` from 10 → 5 (so 100 × 5 = 500 ≤ Aurora's budget), enforced the formula as a pre-flight check before every scale-policy change.

This is the headline story for **why I am a backend engineer who happens to operate infrastructure, not the other way around**: the symptom appeared in EKS metrics, but the root cause was in the Spring Boot connection pool.

### 2. Kafka Non-blocking Retry + DLT

A single broker failure in the early architecture (Version A) produced **3,137 ms P95 latency** and lost order data. The cause was a single-broker SPOF compounded by a Circuit Breaker → Redis fallback path that itself was high-latency.

**Redesign (Version C).** 3-Broker StatefulSet (RF=3, `min.insync.replicas=2`) with `@RetryableTopic` and a non-blocking retry pipeline:

```
order-events (origin)
  │ failure
  ├─ order-events-retry-0  (1 s   delay)   ← network jitter
  │   │ failure
  ├─ order-events-retry-1  (5 s   delay)   ← DB back-pressure
  │   │ failure
  ├─ order-events-retry-2  (30 s  delay)   ← serious infra failure
  │   │ failure
  └─ order-events.DLT                       ← manual replay
```

**Result (broker-1-down chaos test, 100 users):**

| Metric | Version A | **Version C** |
|---|---|---|
| Throughput | 0.4 req/s | **3.3 req/s** |
| P95 latency | 3,137 ms | **436 ms (–87 %)** |
| Order data | **lost** | **preserved** |

7 Micrometer custom counters (`order_success_total`, `order_retry_total{stage=0|1|2}`, `order_dlt_total`, `kafka_retry_total`, `dlt_messages_total`) make the failure layer identifiable from the dashboard alone — a stage-2 spike means infra failure, a stage-0 spike means transient network jitter, and so on.

### 3. Cold Start Defense — KEDA Warm-up + Karpenter

Sale-open traffic was arriving 2 minutes faster than EKS could provision new nodes, producing a cold-start dip in the first 30 seconds.

**Resolution.**
- **Cron-triggered warm-up.** KEDA `cron` trigger raises `minReplicaCount` to 10 starting 23:50 KST (the night before each sale).
- **Aggressive scaleUp.** `50 pods / 30 s` policy (vs default 10 / 30 s).
- **Karpenter consolidation.** All-Spot node pool with `consolidationPolicy: WhenUnderutilized` for cost recovery during off-peak.

In the final load test, scale-out completed within 60 seconds of the load arriving — verified in the Datadog evidence files.

### 4. DevSecOps in CI

Three CI-side security automations I owned:

- **Trivy.** CVE scanning step in the GitLab pipeline; build fails on high/critical findings (with one historical Tomcat CVE patched through this gate).
- **ECR auto-scan.** Every image push triggers AWS ECR vulnerability scan; results visible in the AWS console.
- **Renovate.** Automated dependency-update PRs with grouped patches and weekly schedule for non-urgent updates.

The boundary: I do NOT claim authorship of WAF/KMS/Cloud-Custodian *policy content*. Those are teammate-owned. I integrated them only as Terraform module references.

---

## 🛠️ Trouble-shootings (10 verified)

| # | Problem | Root cause | Resolution | Layer |
|---|---|---|---|---|
| 1 | Kafka broker failure → P95 3,137 ms | Single-broker SPOF + CB → Redis fallback latency | 3-Broker + Non-blocking Retry + DLT | Messaging |
| 2 | KEDA not scaling | `Deployment.spec.replicas` overrode HPA | Removed the `replicas` field entirely | K8s |
| 3 | Sale-open cold start | `minReplicas=2` insufficient | Cron trigger + `minReplicas=10` warm-up | KEDA |
| 4 | EKS node provisioning failed 3× | Managed Node Group structural conflict | Migrated to Karpenter; resolved 16 cascading errors | Infra |
| 5 | Aurora "Too many connections" | `maxReplicas × pool_size > max_connections` | Derived formula; reduced pool 10 → 5 | **Backend ↔ DB** |
| 6 | ArgoCD selfHeal overwrote Secret | Secret defined inside git YAML | Removed Secret YAML; CI-only injection | GitOps |
| 7 | ArgoCD didn't deploy new image | `latest` tag → manifest unchanged → no diff | Commit-SHA tag + `update-manifest` job | CI/CD |
| 8 | Mixed Content blocking | CloudFront cached old JS + hard-coded `http://` | Relative paths + CI cache invalidation | Frontend ops |
| 9 | Terraform circular dependency | RDS ↔ Secrets cycle | Removed `db_host` from Secrets module | IaC |
| 10 | istio-proxy OOMKilled at 150 K VU | Memory limit 256 Mi insufficient | Limit raised to 10 Gi; request/limit separated | Service mesh |

Each item has corresponding commit history in this repository.

---

## 📊 Engineering Reflection — Expected vs Measured RPS

**Expected (theoretical) at 150 K VU:** ~112 K RPS.
**Measured at peak:** 56.3 K RPS.

The gap was not an error — it was two compounding effects:

1. **Iteration period stretch.** Under load, server response time grew, which extended the k6 VU iteration period from ~10 s to 20 s+. Each VU's effective RPS contribution halved during the steady state.
2. **Sidecar overhead.** Every request traverses an Istio sidecar; the proxy's per-hop cost throttled aggregate throughput.

**Conclusion.** 56.3 K RPS was achieved with **zero error budget consumed**, on **all-Spot instances**, with **60-second responsiveness** to the load arrival via KEDA + Karpenter. This is the correct number to defend in interviews — not the theoretical 112 K.

---

## 📁 Project Structure

```
Clmakase/
├── backend/
│   └── src/main/java/com/oliveyoung/sale/
│       ├── config/                          # Redis, Kafka, init data
│       ├── controller/                      # REST controllers
│       ├── domain/                          # Entities (Product, PurchaseOrder)
│       ├── dto/
│       ├── repository/
│       └── service/
│           ├── KafkaProducerService.java
│           ├── KafkaClusterConsumerService.java
│           └── OrderConsumerService.java    # Order processing + Non-blocking Retry
├── frontend/                                # React app
├── k8s/
│   ├── deployment.yaml                      # No replicas field — KEDA-only control
│   ├── keda/
│   │   ├── scaled-object.yaml               # Composite trigger
│   │   └── trigger-auth-datadog.yaml
│   ├── node-class.yaml                      # Karpenter EC2NodeClass
│   ├── node-pool.yaml                       # Karpenter NodePool (Spot)
│   ├── istio/
│   └── monitoring/
├── terraform/
│   ├── main.tf
│   ├── karpenter_iam.tf
│   └── modules/                             # 16 modules
├── custodian/                               # (team-led)
├── k6/
│   └── load-test.js
├── evidence/
│   └── load-test-2026-02-26/                # Datadog screenshot + reports
├── docker-compose-version-a.yml             # Single-broker baseline
├── docker-compose-version-c.yml             # 3-broker + Retry
└── .gitlab-ci.yml                           # 8-stage pipeline
```

---

## 🌐 API Reference (selected)

### Products
- `GET /api/products`
- `GET /api/products/{id}`

### Sale lifecycle
- `GET  /api/sale/status`
- `POST /api/sale/start`
- `POST /api/sale/end`

### Queue
- `POST /api/queue/enter`
- `GET  /api/queue/status`

### Purchase
- `POST /api/purchase`

Common response shape:
```json
{
  "success": true,
  "data": { },
  "message": "...",
  "errorCode": null
}
```

---

## 🚀 Local Development

### Version A (single broker + Circuit Breaker)
```bash
docker-compose -f docker-compose-version-a.yml up -d
# Frontend:  http://localhost:3000
# Backend:   http://localhost:8081
```

### Version C (3-broker + Non-blocking Retry)
```bash
docker-compose -f docker-compose-version-a.yml down
docker-compose -f docker-compose-version-c.yml up -d
# Backend: http://localhost:8082
```

### A/B comparison load test (local)
```powershell
# Windows PowerShell
.\load-test-compare.ps1
```

---

## ❓ Engineering Decisions Q&A

### Q. Why Kafka instead of SQS?
1. **Partition-keyed ordering.** `productId`-based partitioning preserves per-product order and parallelizes across products.
2. **Full retry control.** SQS DLQ is one-shot; `@RetryableTopic` lets us stratify retries by failure cause at the code level.
3. **Replay.** DLT preserves failed messages for analyzed re-processing — non-negotiable for revenue data.
*Trade-off accepted: more operational surface area (StatefulSet management, broker IDs, RF tuning).*

### Q. Why Karpenter instead of Managed Node Group?
Managed Node Group hit `NodeCreationFailure` three times in succession. After confirming a structural conflict given the team's existing Karpenter setup, we migrated wholesale. Auto instance-family selection plus mixed Spot economics were a bonus, not the driver.

### Q. Why Redis Sorted Set for the queue?
- `score = timestamp` → FIFO ordering
- `ZRANK` → O(log N) rank lookup
- `ZADD` / `ZREM` → atomic operations under concurrency
- Centralized state across multiple EKS pods

### Q. How did you set Readiness/Liveness probes?
```yaml
readinessProbe:
  initialDelaySeconds: 90    # Spring boot ~80 s + buffer
  failureThreshold: 5
livenessProbe:
  initialDelaySeconds: 150
  failureThreshold: 5
```
`initialDelaySeconds` must be at least the actual app boot time + ~10 s. Aggressive probes terminate healthy pods that are still starting.

---

## 📚 Lessons Learned

1. With KEDA, **always remove `Deployment.spec.replicas`**.
2. **Never define Secrets in git YAML** — ArgoCD selfHeal will fight you.
3. **Use commit SHA as the image tag** — `latest` makes ArgoCD blind to changes.
4. **Pre-calculate** `maxReplicas × pool_size` against Aurora `max_connections` before every scale change.
5. Probe `initialDelaySeconds` = real boot time + 10 s minimum.
6. Scale-out is **reactive**; sale-open requires **proactive warm-up**.
7. **Build success ≠ deploy success** — verify the manifest-update step closes the loop between CI and CD.

---

## 🚧 Roadmap

- Architecture diagram in PNG/Mermaid (replacing the ASCII version)
- Authentication layer for the queue (HMAC-signed token instead of plain self-issued)
- Multi-region active-active deployment plan
- Public load-test summary post on velog.io/@gm-15

---

## 🤝 Team

- GitHub organization: [github.com/Cloudwave-5-CJ](https://github.com/Cloudwave-5-CJ)
- 🚧 Detailed teamwork & collaboration section to be added (drafting alongside other portfolio projects)

---

## 👤 Author

**Park, Gunwoo (gm-15)** — Software Engineering, Sangmyung University
Backend & Infrastructure Engineering · Team Lead, Clmakase
- GitHub: [github.com/gm-15](https://github.com/gm-15)
- Blog: [velog.io/@gm-15](https://velog.io/@gm-15)
- Email: gunwoo363@gmail.com
