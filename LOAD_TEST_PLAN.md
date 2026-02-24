# 올리브영 세일 시스템 30,000 VU 부하테스트 준비 보고서

> 작성일: 2026-02-24
> 대상 시스템: EKS + Karpenter + KEDA + ArgoCD + GitLab CI
> 목표: 30,000 VU 동시 접속 부하테스트

---

## 1. 시스템 구성 요약

```
[k6 Operator × 5 Pod] → [ALB] → [EKS 앱 Pod]
                                      ↓
                              [Kafka 20 partition]
                                      ↓
                             [KEDA Consumer Pod × 최대 50]
                                      ↓
                              [Aurora RDS MySQL 8.0]
                                      ↑
                              [Redis cache.r7g.large]
```

| 구성 요소 | 변경 전 | 변경 후 |
|----------|--------|--------|
| k6 실행 방식 | 단일 Pod CLI | k6 Operator parallelism:5 |
| VU 규모 | ~5,000 VU | 30,000 VU (6,000 × 5) |
| Karpenter 노드 | xlarge 미포함 | xlarge, 2xlarge, 4xlarge 추가 |
| Karpenter arch | arm64 + amd64 | amd64 전용 (GitLab CI 빌드 호환) |
| KEDA maxReplicas | 20 | 50 |
| Kafka 파티션 수 | 3 | 20 |
| Redis 인스턴스 | cache.t3.micro | cache.r7g.large |
| 상품 재고 | 이전 테스트 소진 | 8개 상품 × 3,000개 = 24,000개 |

---

## 2. 수정된 파일 목록

### k6/load-test.js
```js
export const options = {
    stages: [
        { duration: '2m',  target: 30000 },  // 램프업
        { duration: '13m', target: 30000 },  // 유지
        { duration: '5m',  target: 0     },  // 램프다운
    ],
    thresholds: {
        http_req_duration: ['p(95)<5000'],
        http_req_failed: ['rate<0.1'],
    },
};
```

### k8s/keda/scaledobject.yaml
- `maxReplicaCount`: 20 → **50**
- Kafka `lagThreshold`: "50" → **"20"**
- `activationLagThreshold`: "10" → **"5"**
- `allowIdleConsumers`: "false" → **"true"**
- cron `desiredReplicas`: "10" → **"20"**

### k8s/node-pool.yaml
- arch: `["arm64","amd64"]` → **`["amd64"]`**
- instance-size 추가: **`["xlarge","2xlarge","4xlarge"]`**
- `consolidateAfter`: 3s → **30s**
- 리소스 상한: **cpu:"200", memory:"400Gi"**

### k8s/kafka.yaml
- `KAFKA_NUM_PARTITIONS`: "3" → **"20"**

### k8s/k6/configmap.yaml (신규 생성)
- namespace: `k6-operator`
- load-test.js 스크립트 포함

### k8s/k6/testrun.yaml (신규 생성)
- parallelism: **5**
- runner resources: requests 2CPU/4Gi / limits 4CPU/8Gi
- cleanup: **"post"**

---

## 3. 트러블슈팅 기록

### 3-1. git push 실패 (207MB argocd.exe)
- **원인**: 커밋에 argocd.exe(217MB) 포함
- **해결**: `git filter-branch --tree-filter "rm -f argocd.exe"` 로 히스토리에서 제거 후 push 성공
- **추가**: terraform/variables.tf 누락 → 별도 커밋으로 보완

### 3-2. EKS 노드 3대 동시 NotReady
- **원인**: ArgoCD 싱크 후 t3.medium 3대 동시 다운
- **증상**: kafka-0 Terminating 고착, kafka-1 OOM 축출, Karpenter Pod 다운
- **해결**: AWS 콘솔에서 노드 그룹 desired 0 → 2/3/6 재설정, 신규 t3.medium 투입

### 3-3. Kafka 브로커 ID 불일치 → Leader:none
- **원인**: 강제 재시작으로 브로커 ID 변경 (1001,1002,1003 → 1017,1018,1020)
- **증상**: 토픽 리더 없음, Consumer `LEADER_NOT_AVAILABLE` 에러
- **해결 순서**:
  1. 토픽 + retry/dlt 변형 전체 삭제
  2. ZooKeeper 삭제 마커 수동 제거
  3. Spring 앱 재기동 → 토픽 자동 재생성 (3 파티션)
  4. `kafka-topics --alter --partitions 20` 으로 증설
- **최종 상태**: PartitionCount:20, RF:3, ISR:1017,1018,1020 정상

### 3-4. TestRun CRD 오류 2건
| 오류 | 원인 | 해결 |
|------|------|------|
| `unknown field "spec.script.configMap.namespace"` | CRD 미지원 필드 | namespace 필드 제거, ConfigMap을 k6-operator 네임스페이스로 이동 |
| `Unsupported value: "ttlSecondsAfterFinished"` | CRD 미지원 값 | `cleanup: "post"` 로 변경 |

---

## 4. DB 작업 내역

```sql
-- 재고 초기화 (8개 상품 × 3,000개)
UPDATE product_option SET stock = 3000 WHERE product_id IN (1,2,3,4,5,6,7,8);

-- 이전 테스트 구매 이력 삭제
DELETE FROM purchase_order WHERE created_at < NOW();
```

- 총 가용 재고: **24,000건** (재고 소진 시나리오 포함)
- DB 접속: `cloudwave-dev-aurora.cluster-chqm4ig82r3p.ap-northeast-2.rds.amazonaws.com`

---

## 5. 현재 인프라 상태 (테스트 중단 시점)

| 항목 | 상태 |
|------|------|
| EKS 노드 그룹 (t3.medium) | 실행 중 (desired: 6) |
| Karpenter NodePool | xlarge+ 설정 적용 완료 |
| Kafka | 3 브로커, 파티션 20 정상 |
| Redis | cache.r7g.large (AWS 콘솔 변경 완료) |
| k6 Operator | Running |
| TestRun | 삭제 후 내일 재실행 예정 |
| ArgoCD | main 브랜치 싱크 완료 |

---

---

## 내일 테스트 체크리스트

### 사전 체크 (테스트 시작 전)

- [ ] **이전 TestRun 잔재 삭제**
  ```bash
  kubectl get testrun -n k6-operator
  kubectl delete testrun oliveyoung-sale-loadtest -n k6-operator 2>/dev/null; true
  ```

- [ ] **Kafka 브로커 + 파티션 정상 확인**
  ```bash
  kubectl exec -n oliveyoung kafka-0 -- kafka-topics --bootstrap-server localhost:9092 --describe --topic queue-entry-requests
  # PartitionCount:20, ISR 3개 브로커 확인
  ```

- [ ] **DB 재고 초기화 확인**
  ```bash
  kubectl run mysql-client --image=mysql:8.0 --restart=Never -- sleep infinity
  # wait 타임아웃 에러는 무시 (Datadog init 컨테이너가 느림, 1~2분 후 Running됨)
  kubectl get pod mysql-client   # Running 확인 후 아래 exec 실행
  kubectl exec -it mysql-client -- mysql -h cloudwave-dev-aurora.cluster-chqm4ig82r3p.ap-northeast-2.rds.amazonaws.com -u admin -p'Oj!q9OA_:8E9f7TX' -e "SELECT product_id, SUM(stock) FROM clmakase.product_option GROUP BY product_id;"
  kubectl delete pod mysql-client
  # 각 상품 3,000개 확인 (소진됐으면 UPDATE로 리셋)
  ```

- [ ] **k6 Operator 정상 확인**
  ```bash
  kubectl get pods -n k6-operator
  # k6-operator-controller-manager Running 확인
  ```

- [ ] **KEDA ScaledObject 정상 확인**
  ```bash
  kubectl get scaledobject -n oliveyoung
  # READY True 확인
  ```

- [ ] **앱 Pod 정상 확인**
  ```bash
  kubectl get pods -n oliveyoung
  ```

- [ ] **Redis cache.r7g.large 상태 확인** (AWS 콘솔 ElastiCache → 클러스터 Available)

---

### 진행 중 체크

- [ ] **세일 시작 API 호출** ← 반드시 부하테스트 전에 실행
  ```powershell
  $response = Invoke-WebRequest -Uri "https://api.clmakase.click/api/sale/start" -Method Post
  $response.StatusCode   # 200 확인
  $response.Content
  ```

- [ ] **TestRun 시작**
  ```bash
  kubectl apply -f k8s/k6/
  ```

- [ ] **초기화 완료 → 러너 Pod 5개 확인**
  ```bash
  kubectl get pods -n k6-operator
  # oliveyoung-sale-loadtest-1~5 Running 확인
  ```

- [ ] **Karpenter 노드 자동 프로비저닝 확인** (xlarge+ 노드 생성 여부)
  ```bash
  kubectl get nodes
  ```

- [ ] **KEDA 스케일아웃 확인** (Consumer Pod 증가 여부)
  ```bash
  kubectl get pods -n oliveyoung
  ```

- [ ] **Kafka Consumer Lag 모니터링**
  ```bash
  kubectl exec -n oliveyoung kafka-0 -- kafka-consumer-groups --bootstrap-server localhost:9092 --describe --group oliveyoung-consumer
  ```

---

### 사후 체크 (테스트 종료 후)

- [ ] **세일 종료 API 호출**
  ```powershell
  $response = Invoke-WebRequest -Uri "https://api.clmakase.click/api/sale/end" -Method Post
  $response.StatusCode
  ```

- [ ] **k6 결과 수집** (runner Pod 로그에서 summary 확인)
  ```bash
  kubectl logs -n k6-operator -l k6-test=oliveyoung-sale-loadtest --tail=100
  ```

- [ ] **TestRun 삭제** (runner Pod 정리)
  ```bash
  kubectl delete testrun oliveyoung-sale-loadtest -n k6-operator
  ```

- [ ] **Karpenter 노드 자동 회수 확인** (30초 후 xlarge+ 노드 종료)
  ```bash
  kubectl get nodes
  ```

- [ ] **DB 구매 결과 확인**
  ```bash
  # mysql-client Pod로 접속 후
  # SELECT COUNT(*), SUM(total_price) FROM clmakase.purchase_order;
  # SELECT product_id, SUM(stock) FROM clmakase.product_option GROUP BY product_id;
  ```

- [ ] **에러율 / 응답시간 / 처리량 정리** (발표 자료 반영)

- [ ] **비용 절약**: 테스트 후 Redis를 cache.t3.micro로 다운그레이드 (AWS 콘솔 ElastiCache)
