# 카펜터 컨트롤러가 가질 권한 정책
resource "aws_iam_policy" "karpenter_controller" {
  name        = "KarpenterControllerPolicy-${var.project_name}"
  description = "Policy for Karpenter controller to manage EC2 resources"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:CreateFleet",
          "ec2:CreateLaunchTemplate",
          "ec2:CreateTags",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "iam:PassRole",
          "ssm:GetParameter"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# 카펜터 노드 역할(Node Role)에 추가할 KMS 사용 권한 예시
resource "aws_iam_role_policy" "karpenter_node_kms" {
  name = "KarpenterNodeKMS"
  role = "cloudwave-eks-karpenter-node-role" # 노드용 역할 이름과 일치시키세요

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:CreateGrant", # EC2가 볼륨을 붙일 때 반드시 필요
          "kms:DescribeKey"
        ]
        Resource = "*" # alias/aws/ebs 키를 포함한 KMS 리소스 허용
      }
    ]
  })
}

# 2. 신뢰 관계 설정 (가져오신 코드)
data "aws_iam_policy_document" "karpenter_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:karpenter:karpenter"]
    }

    principals {
      identifiers = [module.eks.oidc_provider_arn]
      type        = "Federated"
    }
  }
}

# 3. 역할 생성
resource "aws_iam_role" "karpenter_controller" {
  name               = "KarpenterControllerRole-${var.project_name}"
  assume_role_policy = data.aws_iam_policy_document.karpenter_assume_role_policy.json
}

# 4. 정책 연결
resource "aws_iam_role_policy_attachment" "karpenter_controller_attach" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = aws_iam_policy.karpenter_controller.arn
}