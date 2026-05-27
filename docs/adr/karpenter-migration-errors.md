# ADR: Karpenter 마이그레이션 안정화 과정의 연쇄 에러 추적

> **상태**: Accepted (2026-02-20 ~ 2026-02-21 해결 완료)
> **컨텍스트**: EKS Managed Node Group → Karpenter 전환
> **관련 commit**: `7c9a3fe` (refactor: Managed Node Group 제거), `66ac1b6` (karpenter 트러블슈팅), `8899072` (instance type & Security), `fb9fe12` (IAM roles + Graviton), `8f4ceea` (feature/karpenter-setup merge)

## 배경

`aws_eks_node_group` Terraform Apply 후 `NodeCreationFailure` 3회 연속 발생. 4가지 우회 시도 (Launch Template + 클러스터 SG / `block_device_mappings` 이동 / `ami_type` AL2023→AL2 / `cluster_version` 1.29→1.30) 모두 실패. 팀이 이미 Karpenter 도입을 진행 중이어서 Managed Node Group을 완전 제거하고 Karpenter 단일 운영으로 전환 결정.

전환 과정에서 발생한 연쇄 에러를 **개별 추적 → 원인 파악 → 해결 → 예방** 4단계로 문서화합니다. 본 문서는 포트폴리오 PDF (CloudWave 부하/CICD파트 7-8쪽) 표와 git commit 로그, HANDOFF_PROMPT.md를 cross-reference한 결과입니다.

## 명시 에러 8건

각 항목은 발생 → 원인 → 해결 순.

### 1. ALB Controller webhook 호출 실패

| 항목 | 내용 |
|---|---|
| 에러 | `failed calling webhook "mservice.elbv2.k8s.aws"` |
| 원인 | 노드가 한 대도 없는 상태에서 ALB Controller webhook endpoint가 미존재. webhook은 노드에서 동작 |
| 해결 | mutating/validating webhook 임시 수동 삭제 후 Karpenter 노드 프로비저닝 → 노드 Ready 이후 webhook 재등록 |
| 예방 | 부트스트랩 노드는 Fargate Profile로 분리 |

### 2. Karpenter CRD `EC2NodeClass` not found

| 항목 | 내용 |
|---|---|
| 에러 | `error: no matches for kind "EC2NodeClass" in version "karpenter.k8s.aws/v1beta1"` |
| 원인 | 구버전 Helm repo (v0.16.x)가 v1alpha5만 지원. v1beta1 CRD 미설치 상태에서 매니페스트 적용 |
| 해결 | Karpenter를 OCI registry에서 v1.0.1로 재설치하여 v1beta1 CRD 정상 등록 |
| 예방 | Helm chart 버전을 명시적으로 pin (`--version 1.0.1`) |

### 3. CoreDNS Pending → DNS 전체 불가 (닭과 달걀)

| 항목 | 내용 |
|---|---|
| 에러 | CoreDNS Pod `Pending` 상태 지속, 결과로 클러스터 내부 DNS 전체 마비 |
| 원인 | Managed Node Group 제거 후 CoreDNS를 스케줄링할 노드 없음 → Karpenter는 DNS 없어 정상 동작 불가 → CoreDNS 다시 노드 못 잡음 (전형적 chicken-and-egg) |
| 해결 | CoreDNS 전용 Fargate Profile 생성 (`coredns-fargate`). EKS Fargate가 노드 없이 Pod 실행 가능 |
| 예방 | CoreDNS / Karpenter 같은 시스템 컴포넌트는 Fargate Profile에 분리 운영 |

### 4. Karpenter Controller Pod Pending

| 항목 | 내용 |
|---|---|
| 에러 | Karpenter Controller Pod이 `Pending` 상태에서 진행 안 됨 |
| 원인 | Karpenter Controller 자신이 노드를 띄우려면 일단 노드 위에서 실행돼야 하는데, 첫 노드를 띄울 권한이 자기 자신에게 있음 (또 다른 chicken-and-egg) |
| 해결 | karpenter 네임스페이스 전용 Fargate Profile (`karpenter-fargate`) 생성. Karpenter Controller만 Fargate에서 영구 실행 |
| 예방 | 시스템 plane (kube-system, karpenter, coredns)은 worker node에 의존하지 않도록 설계 |

### 5. Karpenter Controller `eks:DescribeCluster` AccessDeniedException

| 항목 | 내용 |
|---|---|
| 에러 | `operation error EKS: DescribeCluster, https response error StatusCode: 403, AccessDeniedException` |
| 원인 | Terraform이 만든 `KarpenterControllerRole-cloudwave` 의 정책에 `eks:DescribeCluster` 권한 누락. Karpenter는 클러스터 endpoint 조회를 위해 필수 |
| 해결 | IAM inline policy `KarpenterEKSDescribe` 추가 (`eks:DescribeCluster` 권한 부여) |
| 예방 | Karpenter 공식 IAM 권한 가이드의 모든 액션을 Terraform 모듈에 코드화 (현재 inline은 Technical Debt) |

### 6. SQS Queue `AWS.SimpleQueueService.NonExistentQueue`

| 항목 | 내용 |
|---|---|
| 에러 | `AWS.SimpleQueueService.NonExistentQueue: The specified queue does not exist for this wsdl version` |
| 원인 | Karpenter Helm values에 `settings.interruptionQueue: cloudwave-eks` 가 설정되어 있는데 해당 SQS Queue가 미생성. 본 프로젝트는 Spot Interruption Handler를 사용하지 않기로 결정 |
| 해결 | Helm values에서 `interruptionQueue` 설정 자체를 제거 |
| 예방 | SQS-based graceful drain은 다음 사이클 백로그 (Technical Debt: "Karpenter Spot Interruption Handler 재도입") |

### 7. `consolidateAfter` ↔ `WhenUnderutilized` 정책 충돌

| 항목 | 내용 |
|---|---|
| 에러 | NodePool 적용 시 `consolidateAfter cannot be combined with consolidationPolicy: WhenUnderutilized` |
| 원인 | Karpenter v1.0.x에서 두 옵션이 상호 배타. `WhenUnderutilized`는 자체적 throttling 보유 |
| 해결 | `consolidateAfter` 필드 제거 (commit `7c9a3fe` `node-pool.yaml: consolidateAfter 제거`) |
| 예방 | NodePool spec 변경 시 Karpenter 버전별 호환성 매트릭스 사전 확인 |

### 8. Karpenter v0.37.0 vs v1.0.4 CRD 충돌

| 항목 | 내용 |
|---|---|
| 에러 | `karpenter-65dc46b49-ftj4h` CrashLoopBackOff. `no matches for kind "NodeClaim" in version "karpenter.sh/v1"` |
| 원인 | Helm 릴리스 v0.37.0 (v1beta1)과 v1.0.4 (v1)가 동시 존재. v1.0.4는 v1 CRD 필요하지만 클러스터엔 v1beta1만 등록 |
| 해결 | v1.0.1 단일 버전으로 통일. v0.37.0 Helm 릴리스 삭제, CrashLoop Pod 정리 |
| 예방 | Helm 릴리스 충돌 방지 — 동일 컴포넌트 두 버전 동시 설치 금지 |

## 카테고리 묶음 추가 에러 (포트폴리오 "+8")

포트폴리오 PDF 표에서 "...+8개 추가 에러 (SG 중복, CIDR 충돌, ENI 블로킹 등)"으로 묶여있는 부분의 실제 작업 항목을 git/HANDOFF에서 cross-reference:

### A. Security Group 중복 / 태그 누락 (commit `fb9fe12`, `8899072`)

- Karpenter discovery 태그 (`karpenter.sh/discovery: cloudwave-dev-vpc`) 가 VPC·Subnet·SG 모두에 부여돼야 NodePool이 자원 자동 발견
- 초기 SG 중복 생성 → 태그 충돌 → Karpenter가 잘못된 SG 선택. 태그 명확화 + 중복 SG 제거로 해결

### B. CIDR / 서브넷 ENI 할당 실패

- Private App 서브넷 CIDR이 `10.0.1.0/24` 단일이었던 초기 설정에서 Karpenter가 4xlarge+ 인스턴스 띄울 때 ENI 할당 실패 ("subnet does not have enough free addresses")
- VPC 2 서브넷 → 4 서브넷(App/Data 분리)으로 확장 후 해소 (관련 HANDOFF: "VPC 2서브넷 → 4서브넷 확장")

### C. 부트스트랩 노드 (Managed Node Group으로 임시) → aws-auth ConfigMap

- Karpenter 자체가 첫 노드를 못 띄우는 chicken-and-egg를 우회하기 위해 CLI로 임시 Managed Node Group 1대 수동 생성 (HANDOFF: "부트스트랩용 Managed Node Group으로 수동 생성")
- 임시 노드의 IAM Role을 `aws-auth` ConfigMap에 추가 등록해야 노드가 클러스터에 join 가능

이 3개 카테고리 안에 SG 중복 / CIDR 부족 / ENI 블로킹 / 부트스트랩 노드 / aws-auth ConfigMap / Fargate Pod Execution Role 생성 등 6~8건의 개별 작업이 묶여 있어 포트폴리오 표가 "+8"로 집계한 것입니다.

## 결과

- 16건 (8 explicit + ~8 categorized) 전부 해결 후 `terraform apply` 최종 성공
- 노드 2대 → 최대 26대 자동 프로비저닝 (신규 23대)
- Pod 1 → 100개 자동 스케일아웃 (KEDA maxReplicas)
- 인스턴스 c8i-flex, m7i-flex, r8i 혼합 자동 선택 → 비용 최적화
- Bootstrap Managed Node Group은 안정화 후 제거 (HANDOFF의 "해결 필요 사항 #3" 완료)

## 남은 부채 (Technical Debt와 연결)

- **IaC 드리프트**: Fargate Profile, Karpenter IAM inline policy는 여전히 수동 생성 상태. `terraform import` 또는 신규 모듈화 예정
- **Spot Interruption Handler 미도입**: SQS 기반 graceful drain 흐름 재도입 필요
- 본 ADR은 *발생 시점 (2026-02-20 ~ 02-21)* 기준 사실 기록이며, 이후 환경 정리는 메인 README의 Technical Debt 섹션 참조

## 참고

- README.md / README.en.md 트러블슈팅 표 #4 행에서 본 ADR로 링크
- 포트폴리오 PDF (CloudWave 부하/CICD파트 7-8쪽) 원본 표
- `HANDOFF_PROMPT.md`: 본 프로젝트 핸드오프 시점 클러스터 상태
- git commit: `7c9a3fe`, `66ac1b6`, `8899072`, `fb9fe12`, `8f4ceea`, `22e7e06`
