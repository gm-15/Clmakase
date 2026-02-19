################################################################################
# ALB Controller Module - Main
# CJ Oliveyoung CloudWave Infrastructure
#
# Creates: IAM Policy + IRSA Role + Helm Release
# - AWS ALB Ingress Controller for EKS
# - OIDC 기반 IAM Role for Service Account (IRSA)
################################################################################

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ------------------------------------------------------------------------------
# IAM Policy for ALB Controller
# - ALB/NLB/TargetGroup 등 생성/관리 권한
# ------------------------------------------------------------------------------
resource "aws_iam_policy" "alb_controller" {
  name   = "${local.name_prefix}-alb-controller-policy"
  policy = file("${path.module}/iam-policy.json")

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-alb-controller-policy"
  })
}

# ------------------------------------------------------------------------------
# IRSA Role for ALB Controller
# - K8s ServiceAccount → IAM Role 매핑
# - OIDC Trust Policy로 특정 SA만 assume 가능
# ------------------------------------------------------------------------------
resource "aws_iam_role" "alb_controller" {
  name = "${local.name_prefix}-alb-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.cluster_oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${var.cluster_oidc_provider_url}:aud" = "sts.amazonaws.com"
            "${var.cluster_oidc_provider_url}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          }
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-alb-controller-role"
  })
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  policy_arn = aws_iam_policy.alb_controller.arn
  role       = aws_iam_role.alb_controller.name
}

# ------------------------------------------------------------------------------
# Helm Release - AWS Load Balancer Controller
# ------------------------------------------------------------------------------
resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = var.chart_version

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.alb_controller.arn
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  depends_on = [
    aws_iam_role_policy_attachment.alb_controller,
  ]
}
