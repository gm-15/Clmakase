# CloudWave OliveYoung EKS 인프라 프로젝트 - 이어가기 프롬프트

아래 내용을 새 대화에 붙여넣으세요.

---

## 프로젝트 개요
- **프로젝트**: CJ OliveYoung 대규모 세일 이벤트 시스템 (CloudWave 7기 파이널)
- **도메인**: clmakase.click
- **리포**: C:\Users\KDT49\Clmakase
- **AWS 리전**: ap-northeast-2, 계정 ID: 160884802838

## 아키텍처
- **VPC**: 10.0.0.0/16, 6개 서브넷 (Public 2 + Private App 2 + Private Data 2)
  - Public: 10.0.101.0/24, 10.0.102.0/24 (ALB)
  - Private App: 10.0.1.0/24, 10.0.2.0/24 (EKS 노드)
  - Private Data: 10.0.11.0/24, 10.0.12.0/24 (RDS/ElastiCache)
- **EKS**: cloudwave-eks, v1.30, OIDC/IRSA 활성화
- **노드 관리**: Karpenter (Managed Node Group 제거함)
- **데이터**: Aurora MySQL + ElastiCache Redis
- **배포**: ArgoCD GitOps
- **Ingress**: AWS ALB Controller

## Terraform 구조
```
terraform/
├── main.tf              # VPC, SG, ECR, RDS, EKS, ElastiCache, ALB Controller, ArgoCD, CLI 모듈
├── variables.tf         # 루트 변수 (project_name=cloudwave, env=dev 등)
├── karpenter_iam.tf     # Karpenter Controller IAM Role + Policy (팀원 작성)
├── modules/
│   ├── vpc/             # 6서브넷, NAT GW, karpenter.sh/discovery 태그
│   ├── security-groups/ # ALB, Control Plane, Node, RDS, Redis, CLI, VPC Endpoint SG
│   ├── eks/             # 클러스터 + OIDC (Node Group 제거됨, Karpenter 전환)
│   ├── ecr/
│   ├── rds/
│   ├── elasticache/
│   ├── alb-controller/
│   ├── argocd/
│   ├── cli/             # 구 bastion, 팀원이 리네임
│   ├── secrets/
│   └── ... (waf, kms, s3, route53, acm, cloudfront)
```

## K8s 매니페스트 (k8s/)
- deployment.yaml: Spring Boot 앱, ECR 이미지, Aurora/Redis/Kafka 연결
- hpa.yaml: CPU 60%/Memory 70%, min:2 max:10
- ingress.yaml: ALB internet-facing
- node-class.yaml: Karpenter EC2NodeClass (AL2023, ami-0428587635697666f)
- node-pool.yaml: Karpenter NodePool (arm64+amd64, c/m/r 6세대+)
- db-secret.yaml: DB 자격증명 시크릿 템플릿

## 현재 클러스터 상태 (2026-02-20 기준)

### 정상 동작 중 ✅
- ArgoCD: 5개 Pod 모두 Running (argocd 네임스페이스)
- ALB Controller: 2개 Pod Running (kube-system)
- CoreDNS: 2개 Pod Running (kube-system, Fargate)
- Karpenter v0.37.0: 1개 Pod Running (karpenter-545ff4f74d-rj25k)
- EKS Node: 1대 (부트스트랩용 Managed Node Group으로 수동 생성)

### 문제 상태 ❌
- **Karpenter v1.0.4 Pod 2개 CrashLoopBackOff**: `karpenter-65dc46b49-ftj4h`, `karpenter-65dc46b49-hwwvt`
  - 에러: `no matches for kind "NodeClaim" in version "karpenter.sh/v1"`
  - 원인: v1.0.4는 v1 CRD 필요, 현재 클러스터엔 v1beta1 CRD만 있음
  - v0.37.0과 v1.0.4가 동시에 Helm 릴리스로 존재

### 해결 필요 사항
1. **Karpenter 버전 통일**: v0.37.0(v1beta1)과 v1.0.4(v1) 중 하나로 통일
   - v0.37.0 유지 시: v1.0.4 릴리스 삭제, CrashLoop Pod 정리
   - v1.0.4로 올릴 시: CRD를 v1으로 업그레이드 필요, node-class.yaml/node-pool.yaml도 v1 API로 변경
2. **CrashLoop Pod 정리**: 불필요한 Karpenter Pod 삭제
3. **부트스트랩 노드그룹 정리 여부 결정**: Karpenter 안정화 후 삭제 가능

## 이전 대화에서 수행한 주요 작업
1. Version A(단일 Kafka) vs Version C(3-Broker Kafka) 로컬 부하테스트 + 장애시뮬레이션 완료
2. VPC 2서브넷 → 4서브넷(App/Data 분리) 확장
3. Terraform 순환참조(RDS↔Secrets), 중복리소스 수정
4. EKS Managed Node Group → Karpenter 전환 (eks/main.tf에서 node_group 제거)
5. Fargate Profile 생성 (karpenter, coredns 네임스페이스)
6. aws-auth ConfigMap에 노드 IAM Role 등록
7. Karpenter Controller IAM에 eks:DescribeCluster 권한 추가
8. SQS interruptionQueue 제거 (불필요)
9. 팀원 코드 머지 (Karpenter IAM, KEDA, CLI 모듈)
10. terraform apply 최종 성공 (VPC, SG, ECR, RDS, EKS, ElastiCache, ALB, ArgoCD)

## AWS에서 수동으로 생성한 리소스 (Terraform 외)
- Fargate Profile: karpenter-fargate, coredns-fargate
- IAM Role: cloudwave-fargate-pod-execution-role
- IAM Inline Policy: KarpenterEKSDescribe (KarpenterControllerRole-cloudwave에)
- SQS Queue: cloudwave-eks (사용 안 함, 삭제 가능)
- 부트스트랩용 Managed Node Group (CLI로 수동 생성)

## 주요 IAM Role ARN
- EKS Node Role: arn:aws:iam::160884802838:role/cloudwave-dev-eks-node-role
- Karpenter Controller: arn:aws:iam::160884802838:role/KarpenterControllerRole-cloudwave
- Fargate Pod Execution: arn:aws:iam::160884802838:role/cloudwave-fargate-pod-execution-role

## Helm 바이너리 경로
- C:\Users\KDT49\helm\windows-amd64\helm.exe (PATH에 없음, 절대경로로 실행)

## node-class.yaml 현재 내용
```yaml
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: AL2023
  amiSelectorTerms:
    - id: "ami-0428587635697666f"
  role: "cloudwave-eks-karpenter-node-role"
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 50Gi
        volumeType: gp3
        encrypted: true
        deleteOnTermination: true
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "cloudwave-dev-vpc"
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: "cloudwave-dev-vpc"
```

## node-pool.yaml 현재 내용
```yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: security-optimized-pool
spec:
  template:
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["arm64", "amd64"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand", "spot"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c", "m", "r"]
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["6"]
      nodeClassRef:
        name: default
  disruption:
    consolidationPolicy: WhenUnderutilized
    expireAfter: 720h
```

## 다음 해야 할 작업
1. Karpenter 버전 충돌 해결 (v0.37.0 vs v1.0.4 통일)
2. Karpenter가 실제로 노드를 프로비저닝하는지 확인
3. 부트스트랩 노드그룹 정리
4. 앱 이미지 ECR 푸시 + kubectl apply로 앱 배포
5. ALB Ingress 동작 확인 (도메인 연결)
6. 전체 시스템 통합 테스트

## 규칙
- 토큰 절약: 불필요한 파일 읽기 X, 변경사항만 diff로 보여주기, 코드 설명 생략
- 푸시는 명시적 요청 시에만
- 한국어로 소통
