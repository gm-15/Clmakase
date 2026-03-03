# OliveYoung 대규모 세일 이벤트 시스템

> **CloudWave 7기 파이널 프로젝트**
> AWS EKS 기반 고가용성 세일 이벤트 처리 시스템
> 도메인: `clmakase.click` | 리전: `ap-northeast-2`

---

## 핵심 성과

| 지표 | 결과 |
|------|------|
| 최대 동시 접속자 | **150,000 VU** |
| 피크 RPS | **56,300 hits/s** (Datadog 실측) |
| 안정 RPS | **49,500 hits/s** (피크 구간 평균) |
| 총 처리 요청 수 | **4.65M hits** (20분) |
| Success Rate | **100%** (5xx 에러 0건) |
| P99 Latency | **180ms 이하** |
| OOMKilled | **0건** |
| 서비스 중단 | **0건** |
| 최대 API Pod | **100개** (KEDA 자동 스케일) |
| 최대 노드 | **26개** (Karpenter Spot 자동 프로비저닝) |
| 브로커 장애 시 P95 개선 | **3,137ms → 436ms (87%)** |
| 주문 데이터 유실 | **0건** (Non-blocking Retry + DLT) |

---

## 시스템 아키텍처

```
사용자
  │ HTTPS
  ▼
CloudFront ──────────────── S3 (React 정적 호스팅)
  │
  ▼
WAF ─── ALB (api.clmakase.click)
              │
              ▼
        EKS Cluster (ap-northeast-2)
          │
          ├─ oliveyoung-api Pod × 1~100
          │    ├─ KEDA ScaledObject
          │    │    ├─ Kafka consumer lag 트리거
          │    │    ├─ Datadog RPS 트리거
          │    │    └─ Cron 트리거 (세일 오픈 Warm-up)
          │    └─ Istio sidecar (mTLS)
          │
          ├─ Kafka 3-Broker StatefulSet
          │    └─ Zookeeper (리더 선출·offset 관리)
          │
          ├─ Karpenter NodePool
          │    └─ c/m/r 패밀리 6세대+, 전량 Spot
          │
          └─ ArgoCD (GitOps selfHeal + prune)
               │
               ├─ Aurora MySQL (Multi-AZ, HikariCP pool 5)
               └─ ElastiCache Redis (대기열 상태 캐싱)
```

---

## 기술 스택

| 영역 | 기술 |
|------|------|
| **오케스트레이션** | EKS v1.30 + Karpenter v1.0.1 |
| **메시징** | Kafka 3-Broker + Zookeeper |
| **오토스케일링** | KEDA (Kafka lag / Datadog RPS / Cron 복합 트리거) |
| **GitOps** | ArgoCD + GitLab CI/CD (8단계 파이프라인) |
| **서비스 메시** | Istio mTLS + Kiali |
| **데이터** | Aurora MySQL (Multi-AZ) + ElastiCache Redis |
| **IaC** | Terraform 16개 모듈 |
| **모니터링** | Datadog APM + Prometheus (Kiali 전용) |
| **보안** | WAF + KMS + Secrets Manager + Trivy |
| **CDN** | CloudFront + S3 + ACM + Route53 |
| **백엔드** | Spring Boot + Micrometer (커스텀 메트릭 7종) |

---

## 프로젝트 구조

```
Clmakase/
├── backend/
│   └── src/main/java/com/oliveyoung/sale/
│       ├── config/             # Redis, Kafka, 초기 데이터 설정
│       ├── controller/         # REST API 컨트롤러
│       ├── domain/             # 엔티티 (Product, PurchaseOrder)
│       ├── dto/                # 요청/응답 DTO
│       ├── repository/         # JPA Repository
│       └── service/
│           ├── KafkaProducerService.java       # 이벤트 발행
│           ├── KafkaClusterConsumerService.java # 대기열 컨슘
│           └── OrderConsumerService.java        # 주문 처리 + Non-blocking Retry
├── frontend/                   # React 프론트엔드
├── k8s/
│   ├── deployment.yaml         # oliveyoung-api (replicas 필드 없음 — KEDA 전담)
│   ├── keda/
│   │   ├── scaled-object.yaml  # 복합 트리거 ScaledObject
│   │   └── trigger-auth-datadog.yaml
│   ├── node-class.yaml         # Karpenter EC2NodeClass (AL2023, amd64)
│   ├── node-pool.yaml          # Karpenter NodePool (Spot, xlarge~8xlarge)
│   └── monitoring/
│       └── prometheus-values.yaml  # Kiali 전용 (6시간 보존)
├── terraform/
│   ├── main.tf                 # 전체 모듈 오케스트레이션
│   ├── karpenter_iam.tf        # Karpenter IAM (OIDC Trust, Node KMS)
│   └── modules/
│       ├── vpc/                # 6서브넷 (Public/App/Data × 2 AZ)
│       ├── security-groups/    # 7개 SG
│       ├── eks/                # 클러스터 + OIDC
│       ├── ecr/                # oliveyoung-api 레포지토리
│       ├── rds/                # Aurora MySQL Multi-AZ
│       ├── elasticache/        # Redis
│       ├── alb-controller/     # Helm 릴리스
│       ├── argocd/             # Helm 릴리스
│       ├── cli/                # SSM 기반 Bastion
│       ├── secrets/            # Secrets Manager
│       ├── waf/                # WAF
│       ├── kms/                # KMS
│       ├── s3/                 # 프론트엔드 정적 호스팅
│       ├── route53/            # DNS
│       ├── acm/                # SSL 인증서
│       └── cloudfront/         # CDN
├── k6/
│   └── load-test.js            # 부하테스트 시나리오
├── docker-compose-version-a.yml
├── docker-compose-version-c.yml
└── .gitlab-ci.yml              # 8단계 CI/CD 파이프라인
```

---

## CI/CD 파이프라인

```
git push main
  ↓
[1] test            → Gradle JUnit (allow_failure)
[2] build           → Docker → ECR (commit SHA 태그)
[3] trivy-scan      → CVE 취약점 스캔
[4] update-manifest → deployment.yaml SHA 교체 → git push [skip ci]
[5] deploy-secrets  → KEDA Datadog Secret 주입 (git 외부 관리)
[6] deploy-frontend → npm build → S3 → CloudFront 캐시 무효화
[7] load-test       → k6 (when: manual, allow_failure: true)
  ↓
ArgoCD 감지 → EKS 롤링 배포
```

**설계 포인트:**
- commit SHA 태그 → ArgoCD가 변경 감지, 정확한 롤백 지점 확보
- `[skip ci]` → manifest update 커밋의 무한 파이프라인 루프 방지
- Secret은 git에 절대 정의하지 않음 → ArgoCD selfHeal 충돌 방지

---

## 스케일링 아키텍처

### KEDA 복합 트리거

```yaml
triggers:
  - type: kafka       # Kafka consumer lag 기반
  - type: datadog     # RPS 기반
  - type: cron        # 세일 오픈 시각 Warm-up
minReplicaCount: 10   # 세일 전 사전 준비
maxReplicaCount: 100
scaleUp: 50개/30s     # 급격한 트래픽 대응
```

> `Deployment.spec.replicas` 필드를 제거해야 KEDA가 단독으로 Pod 수를 제어합니다.
> 해당 필드가 남아있으면 Deployment Controller와 충돌하여 스케일링이 동작하지 않습니다.

### Karpenter NodePool

```yaml
requirements:
  - key: karpenter.sh/capacity-type
    values: ["spot"]            # 전량 Spot으로 비용 최적화
  - key: node.kubernetes.io/instance-type
    values: [c/m/r 패밀리 6세대+ xlarge~8xlarge]
disruption:
  consolidationPolicy: WhenUnderutilized  # 유휴 노드 자동 반납
```

### DB 연결 수 계산 공식

```
총 DB 연결 수 = maxReplicas × HikariCP pool_size ≤ Aurora max_connections
```

스케일 계획 수립 전 반드시 이 공식으로 연결 버짓을 사전 계산합니다.
현재 설정: `pool_size=5` (기본값 10에서 축소)

---

## Kafka 아키텍처 — Version A vs Version C

### 비교 실험 결과

**브로커 1대 강제 종료 시나리오 (100 Users):**

| 지표 | Version A (단일 브로커 + CB) | Version C (3-Broker + Retry) |
|------|------------------------------|-------------------------------|
| Throughput | 0.4 req/s | 3.3 req/s |
| P95 Latency | **3,137ms** | **436ms** |
| 주문 데이터 | **유실** | **무손실** |

**정상 트래픽 (1,000 Users):**

| 지표 | Version A | Version C |
|------|-----------|-----------|
| Avg Latency | 439ms | **303ms (-31%)** |
| P95 Latency | 859ms | **431ms (-50%)** |

Spring Profile(`version-a` / `version-c`)로 전환하여 동일 인프라에서 아키텍처 차이만 변수로 격리한 비교 실험.

### Non-blocking Retry 토픽 설계

```
order-events (원본)
  │ 실패
  ├─ order-events-retry-0 (1초 후)   ← 네트워크 순간 오류
  │    │ 실패
  ├─ order-events-retry-1 (5초 후)   ← DB 커넥션 부족
  │    │ 실패
  ├─ order-events-retry-2 (30초 후)  ← 심각한 인프라 장애
  │    │ 실패
  └─ order-events.DLT                ← 수동 Replay 대기
```

실패 메시지를 별도 토픽으로 격리 → 원본 파티션의 정상 메시지 처리 미중단.
`productId`를 파티션 키로 사용 → 동일 상품 내 순서 보장 + 다른 상품 병렬 처리.

### Micrometer 커스텀 메트릭 (7종)

```
order_success_total           — 주문 처리 성공
order_retry_total{stage="0"}  — Stage 0 재시도 (네트워크 지터 감지)
order_retry_total{stage="1"}  — Stage 1 재시도 (DB 병목 감지)
order_retry_total{stage="2"}  — Stage 2 재시도 (인프라 장애 감지)
order_dlt_total               — DLT 도달 (긴급 대응 트리거)
kafka_retry_total             — 큐 재시도 횟수
dlt_messages_total            — 큐 DLT 도달
```

stage별 카운터 상승 패턴만으로 장애 계층을 즉시 식별할 수 있도록 설계.

---

## 150,000 VU 부하테스트 결과 (2026-02-26)

**시나리오:** 0 → 150k VU 2분 급상승 → 13분 피크 유지 → 5분 감소 (총 20분)
**구성:** k6 parallelism 10 (파드당 15,000 VU, 8core/16GB)
**측정:** Datadog `as_rate()` 실측 (11:54 ~ 12:14)

### 핵심 성능 지표 (Datadog 실측)

| 지표 | 결과 |
|------|------|
| **Peak RPS** | **56,300 hits/s** |
| **Stable RPS** | **49,500 hits/s** (피크 구간 평균) |
| **총 처리 요청** | **4.65M hits** |
| **Success Rate** | **100%** (5xx 에러 0건) |
| **P99 Latency** | **180ms 이하** |
| OOMKilled | **0건** |
| 서비스 중단 | **없음** |

> **RPS 분석**: 150k VU 기준 이론 최대치(~112k RPS)와 실측치(56k RPS)의 차이는
> 고부하 시 서버 응답시간 증가로 k6 iteration 주기가 ~10s에서 ~20s 이상으로 연장된 것과
> Istio-proxy 사이드카 네트워크 오버헤드가 복합적으로 작용한 결과.

### 스케일링 타임라인

```
T+0:57  k6 VU 상승 시작 — 10개 Pod 사전 Warm-up 완료 (Cold Start 없음)
T+5:45  KEDA 발동 — 10 → 86 Pod (50개/30s 정책)
         Karpenter 노드 12 → 36개 급증
T+6:xx  100 Pod 도달 (maxReplicas 한도)
T+7:xx  r8i.8xlarge(32vCPU/256GB), c8i-flex.4xlarge 대형 노드 안착
T+8~20  150,000 VU 피크 13분 안정 유지 — OOMKilled 0, CrashLoop 0
```

### 피크 인프라 구성 (전량 Spot)

| 인스턴스 | 수량 | vCPU | RAM |
|----------|------|------|-----|
| c8i-flex.xlarge | 15 | 4 | 8GB |
| c8i.xlarge | 5 | 4 | 8GB |
| m7i-flex.xlarge | 2 | 4 | 16GB |
| r8i.8xlarge | 1 | 32 | 256GB |
| c8i-flex.4xlarge | 1 | 16 | 32GB |
| c8i-flex.2xlarge | 1 | 8 | 16GB |
| **합계** | **25** | **~128 core** | **~600GB** |

---

## VPC 네트워크 설계

| 서브넷 | CIDR | 용도 |
|--------|------|------|
| Public-2a/2c | 10.0.101~102.0/24 | ALB, NAT GW |
| Private App-2a/2c | 10.0.1~2.0/24 | EKS 워커 노드 |
| Private Data-2a/2c | 10.0.11~12.0/24 | Aurora, ElastiCache |

---

## API 명세

### 상품

| Method | Endpoint | 설명 |
|--------|----------|------|
| GET | `/api/products` | 상품 목록 조회 |
| GET | `/api/products/{id}` | 상품 상세 조회 |

### 세일

| Method | Endpoint | 설명 |
|--------|----------|------|
| GET | `/api/sale/status` | 세일 상태 조회 |
| POST | `/api/sale/start` | 세일 시작 |
| POST | `/api/sale/end` | 세일 종료 |

### 대기열

| Method | Endpoint | 설명 |
|--------|----------|------|
| POST | `/api/queue/enter` | 대기열 진입 |
| GET | `/api/queue/status` | 대기 순번 조회 |

### 구매

| Method | Endpoint | 설명 |
|--------|----------|------|
| POST | `/api/purchase` | 구매 처리 |

**공통 응답 형식:**
```json
{
  "success": true,
  "data": { },
  "message": "성공 메시지",
  "errorCode": null
}
```

---

## 로컬 실행

### Version A (단일 브로커 + Circuit Breaker)

```bash
docker-compose -f docker-compose-version-a.yml up -d
# 프론트엔드: http://localhost:3000
# 백엔드 API: http://localhost:8081
```

### Version C (3-Broker + Non-blocking Retry)

```bash
# Version A 종료 후 실행 (Kafka 포트 충돌 방지)
docker-compose -f docker-compose-version-a.yml down
docker-compose -f docker-compose-version-c.yml up -d
# 백엔드 API: http://localhost:8082
```

### A/B 비교 부하테스트 (로컬)

```powershell
# Windows PowerShell
.\load-test-compare.ps1
```

---

## 핵심 설계 결정 Q&A

### Q. SQS 대신 Kafka를 직접 구축한 이유는?

1. **파티션 병렬 처리**: `productId` 기반 파티셔닝으로 동일 상품 순서 보장 + 고트래픽 수평 확장
2. **Non-blocking Retry 완전 제어**: SQS DLQ는 단순 구조. `@RetryableTopic`으로 실패 원인별 지연 시간을 코드 레벨에서 세분화
3. **메시지 Replay**: DLT에 보존된 실패 메시지를 원인 분석 후 재처리. 매출 데이터 유실 방지

*트레이드오프: 운영 복잡도 증가. StatefulSet 관리·broker ID 고정·replication factor 직접 핸들링.*

### Q. Managed Node Group 대신 Karpenter를 쓴 이유는?

Managed Node Group이 3회 연속 `NodeCreationFailure`로 실패. 팀이 이미 Karpenter로 전환한 상태에서의 구조적 충돌 확인 후 완전 전환. 인스턴스 패밀리 자동 선택과 Spot 혼합 운용으로 비용 최적화.

### Q. 대기열을 Redis Sorted Set으로 구현한 이유는?

- `score = timestamp` → FIFO 순서 보장
- `ZRANK` → O(log N) 순위 조회
- `ZADD`, `ZREM` → 원자적 연산으로 동시성 안전
- EKS 다중 Pod 환경에서 중앙 상태 관리

### Q. Readiness Probe 설정 기준은?

```yaml
readinessProbe:
  initialDelaySeconds: 90   # Spring 앱 실제 기동시간(~80s) + 여유
  failureThreshold: 5
livenessProbe:
  initialDelaySeconds: 150
  failureThreshold: 5
```

`initialDelaySeconds`는 반드시 실제 앱 기동시간 + 10초 이상 여유를 두어야 합니다.
성급한 probe 설정은 정상 기동 중인 Pod을 강제 종료시킵니다.

---

## 주요 트러블슈팅 요약

| # | 문제 | 원인 | 해결 |
|---|------|------|------|
| 1 | Kafka 브로커 장애 시 P95 3,137ms | 단일 브로커 SPOF + CB Redis fallback 고지연 | 3-Broker + Non-blocking Retry 전환 |
| 2 | KEDA 스케일링 미동작 | `Deployment.spec.replicas` 고정값이 HPA 명령 덮어씀 | replicas 필드 완전 제거 |
| 3 | 세일 오픈 직후 Cold Start 지연 | `minReplicas: 2`로 사전 준비 부족 | Cron 트리거 + `minReplicas: 10` Warm-up |
| 4 | EKS 노드 프로비저닝 3회 실패 | Managed Node Group 구조적 충돌 | Karpenter 전환 + 16개 연쇄 에러 해결 |
| 5 | Aurora Too many connections | `maxReplicas × pool_size` > `max_connections` | 공식 도출 후 pool 10→5 축소 |
| 6 | ArgoCD selfHeal이 Secret 덮어씀 | Secret을 git YAML에 정의 | Secret 블록 제거, CI 전용 주입 |
| 7 | ArgoCD 배포 미동작 | `latest` 태그 → YAML 변경 없음 → 감지 실패 | commit SHA 태그 + update-manifest job |
| 8 | Mixed Content 차단 | CloudFront 구버전 JS 캐싱 + HTTP URL 하드코딩 | 상대경로 변환 + CI 자동 캐시 무효화 |
| 9 | Terraform 순환 참조 | RDS ↔ Secrets 상호 의존 | Secrets에서 db_host 제거 |
| 10 | istio-proxy OOMKilled | 150k VU 트래픽에서 limit 256Mi 초과 | limit 10Gi + request/limit 분리 |

---

## Lessons Learned

```
1. KEDA 사용 시 Deployment.spec.replicas 필드는 반드시 제거
2. Secret은 git에 절대 정의하지 않는다 — ArgoCD selfHeal 충돌
3. 이미지 태그는 SHA — latest는 ArgoCD가 변경을 감지하지 못함
4. DB 연결 수 = maxReplicas × pool_size 사전 계산 필수
5. Probe initialDelay = 앱 실제 기동시간 + 10초 이상 여유
6. 스케일링은 반응형 — 세일 오픈 전 Warm-up 전략 필수
7. 빌드 성공 ≠ 배포 완료 — CI와 CD 사이의 Manifest Update 연결 고리 확인
```
