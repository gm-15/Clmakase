################################################################################
# Root Module - Main
# CJ Oliveyoung CloudWave Infrastructure
#
# Phase 1: VPC + Security Groups + ECR + RDS (Aurora MySQL)
# Phase 2: EKS + Node Group + OIDC (Terraform 자동화)
# Phase 3: ElastiCache (Redis) + ALB Controller + ArgoCD
################################################################################

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
# 서울 리전 명시적 프로바이더
# module "acm_alb"에서 providers = { aws = aws.seoul }로 호출할 때 사용됩니다.
provider "aws" {
  alias  = "seoul"
  region = "ap-northeast-2" # 서울 리전 고정

  default_tags {
    tags = local.common_tags
  }
}

# CloudFront WAF는 us-east-1에서만 생성 가능
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# ------------------------------------------------------------------------------
# Kubernetes & Helm Providers (EKS 클러스터 생성 후 연결)
# - ALB Controller, ArgoCD Helm 배포에 필요
# ------------------------------------------------------------------------------
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
    }
  }
}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ------------------------------------------------------------------------------
# VPC Module
# ------------------------------------------------------------------------------
module "vpc" {
  source = "./modules/vpc"

  project_name              = var.project_name
  environment               = var.environment
  vpc_cidr                  = var.vpc_cidr
  azs                       = var.azs
  public_subnet_cidrs       = var.public_subnet_cidrs
  private_subnet_cidrs      = var.private_subnet_cidrs
  private_data_subnet_cidrs = var.private_data_subnet_cidrs
  cluster_name              = var.cluster_name
  common_tags               = local.common_tags
}

# ------------------------------------------------------------------------------
# Security Groups Module
# ------------------------------------------------------------------------------
module "security_groups" {
  source = "./modules/security-groups"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = module.vpc.vpc_cidr
  common_tags  = local.common_tags
}

# ------------------------------------------------------------------------------
# ECR Module
# ------------------------------------------------------------------------------
module "ecr" {
  source = "./modules/ecr"

  project_name        = var.project_name
  environment         = var.environment
  repository_name     = var.ecr_repository_name
  image_count_to_keep = 10
  common_tags         = local.common_tags
}

# ------------------------------------------------------------------------------
# RDS Module (Aurora MySQL)
# ------------------------------------------------------------------------------
module "rds" {
  source = "./modules/rds"

  project_name       = var.project_name
  environment        = var.environment
  private_subnet_ids = module.vpc.private_data_subnet_ids
  db_password = module.secrets.db_password
  rds_sg_id          = module.security_groups.rds_sg_id
  database_name      = "oliveyoung"
  master_username    = "admin"
  # master_password는 random_password로 자동 생성 → ASM에 보관
  instance_class     = "db.t3.medium"
  common_tags        = local.common_tags
}

# ------------------------------------------------------------------------------
# WAF Module (CloudFront용 - us-east-1)
# ------------------------------------------------------------------------------
module "waf" {
  source = "./modules/waf"

  providers = {
    aws = aws.us_east_1
  }

  project_name = var.project_name
  environment  = var.environment
  common_tags  = local.common_tags
}

# ------------------------------------------------------------------------------
# KMS Module (S3 + CloudFront 데이터 암호화)
# ------------------------------------------------------------------------------
module "kms" {
  source = "./modules/kms"

  project_name = var.project_name
  key_alias    = "${var.project_name}-s3-key"
  common_tags  = local.common_tags
}

# ------------------------------------------------------------------------------
# 비밀번호 관리 (Secrets Manager)
# ------------------------------------------------------------------------------
module "secrets" {
  source          = "./modules/secrets"
  project_name    = var.project_name
  environment     = var.environment
  # [변경 포인트]: RDS 전용 KMS 키를 사용하여 보안성 강화
  kms_key_arn     = module.kms.rds_key_arn
  master_username = var.master_username
  database_name   = var.database_name
  common_tags     = local.common_tags
}

# ------------------------------------------------------------------------------
# S3 Module (정적 자산 버킷 - CloudFront 오리진, KMS 암호화)
# ------------------------------------------------------------------------------
module "s3" {
  source = "./modules/s3"

  project_name = var.project_name
  environment  = var.environment
  kms_key_arn  = module.kms.s3_key_arn
  common_tags  = local.common_tags
}

# ------------------------------------------------------------------------------
# [Step 1] Route53 Module (Hosted Zone만 생성)
# → ACM DNS 검증에 zone_id가 먼저 필요하므로 Zone만 분리
# ------------------------------------------------------------------------------
module "route53" {
  source = "./modules/route53"

  project_name = var.project_name
  domain_name  = var.domain_name
  common_tags  = local.common_tags
}

# ------------------------------------------------------------------------------
# [Step 2] ACM Module (SSL 인증서 - us-east-1, CloudFront 필수)
# → Route53 zone_id로 DNS 자동 검증
# + ALB 용 인증서 (서울 리전 등 서비스 리전)
# ------------------------------------------------------------------------------
# 1. Cloudfront 인증서 (반드시 us-east-1)
module "acm_cloudfront" {
  source = "./modules/acm"

  providers = {
    aws = aws.us_east_1
  }

  project_name    = var.project_name
  domain_name     = var.domain_name
  route53_zone_id = module.route53.zone_id
  common_tags     = local.common_tags
}
# 2. ALB용 인증서 (서울 리전 등 서비스 리전)
module "acm_alb" {
  source = "./modules/acm"

  providers = {
    aws = aws.seoul  # 혹은 기본 aws 프로바이더
  }

  project_name    = var.project_name
  domain_name     = var.domain_name
  route53_zone_id = module.route53.zone_id
  common_tags     = local.common_tags
}

# ------------------------------------------------------------------------------
# [Step 3] CloudFront Module (CDN + WAF + OAC + ACM)
# → ACM 인증서 검증 완료 후 생성
# ------------------------------------------------------------------------------
module "cloudfront" {
  source = "./modules/cloudfront"

  project_name          = var.project_name
  s3_bucket_domain_name = module.s3.bucket_regional_domain_name
  waf_acl_id            = module.waf.web_acl_arn
  domain_name           = var.domain_name
  acm_certificate_arn   = module.acm_cloudfront.certificate_arn
}

# ------------------------------------------------------------------------------
# [Step 4] S3 버킷 정책 (CloudFront OAC 허용)
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_policy" "cloudfront_oac" {
  bucket = module.s3.bucket_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAC"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${module.s3.bucket_arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = module.cloudfront.cloudfront_arn
          }
        }
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# [Step 5] Route53 DNS 레코드 (CloudFront 생성 후 연결)
# → 순환참조 방지를 위해 root에서 직접 생성
# ------------------------------------------------------------------------------

# 루트 도메인 → CloudFront (clmakase.click → d1234.cloudfront.net)
resource "aws_route53_record" "cloudfront" {
  zone_id = module.route53.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = module.cloudfront.cloudfront_domain_name
    zone_id                = module.cloudfront.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}

# www 서브도메인 → 루트 도메인 CNAME
resource "aws_route53_record" "www" {
  zone_id = module.route53.zone_id
  name    = "www.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = [var.domain_name]
}

# ==============================================================================
# Phase 2: EKS Cluster + Node Group
# ==============================================================================

# ------------------------------------------------------------------------------
# EKS Module (Cluster + Managed Node Group + OIDC Provider)
# ------------------------------------------------------------------------------
module "eks" {
  source = "./modules/eks"

  project_name        = var.project_name
  environment         = var.environment
  cluster_name        = var.cluster_name
  cluster_version     = "1.30"
  private_subnet_ids  = module.vpc.private_subnet_ids
  control_plane_sg_id = module.security_groups.eks_control_plane_sg_id
  node_sg_id          = module.security_groups.eks_node_sg_id
  node_instance_types = var.eks_node_instance_types
  node_min_size       = var.eks_node_min_size
  node_desired_size   = var.eks_node_desired_size
  node_max_size       = var.eks_node_max_size
  node_disk_size      = var.eks_node_disk_size
  common_tags         = local.common_tags
}

# ==============================================================================
# Phase 3: ElastiCache + ALB Controller + ArgoCD
# ==============================================================================

# ------------------------------------------------------------------------------
# ElastiCache Module (Redis)
# - 대기열 관리 + 캐시 (EKS와 독립적으로 생성 가능)
# ------------------------------------------------------------------------------
module "elasticache" {
  source = "./modules/elasticache"

  project_name       = var.project_name
  environment        = var.environment
  node_type          = var.redis_node_type
  private_subnet_ids = module.vpc.private_data_subnet_ids
  redis_sg_id        = module.security_groups.redis_sg_id
  common_tags        = local.common_tags
}

# ------------------------------------------------------------------------------
# ALB Controller Module (IRSA + Helm)
# - EKS OIDC Provider 필요 → EKS 모듈 의존
# ------------------------------------------------------------------------------
module "alb_controller" {
  source = "./modules/alb-controller"

  project_name              = var.project_name
  environment               = var.environment
  cluster_name              = module.eks.cluster_name
  cluster_oidc_provider_arn = module.eks.oidc_provider_arn
  cluster_oidc_provider_url = module.eks.oidc_provider_url
  vpc_id                    = module.vpc.vpc_id
  aws_region                = var.aws_region
  common_tags               = local.common_tags
}

# ------------------------------------------------------------------------------
# ArgoCD Module (Helm)
# - GitOps 기반 K8s 배포 자동화
# - EKS 클러스터 필요 → EKS 모듈 의존
# ------------------------------------------------------------------------------
module "argocd" {
  source = "./modules/argocd"

  project_name = var.project_name
  environment  = var.environment
  common_tags  = local.common_tags
}

# ------------------------------------------------------------------------------
# Bastion (CLI Server) Module
# - SSM 기반 Private CLI 서버 (SSH 없이 접근)
# ------------------------------------------------------------------------------
module "cli" {
  source = "./modules/cli"

  vpc_id         = module.vpc.vpc_id
  project_name   = var.project_name
  environment    = var.environment
  aws_region     = var.aws_region
  nat_gateway_id = module.vpc.nat_gateway_ids[0]
  cli_sg_id      = module.security_groups.cli_sg_id
  vpce_sg_id     = module.security_groups.vpce_sg_id
  common_tags    = local.common_tags
}
