################################################################################
# Root Module - Main
# CJ Oliveyoung CloudWave Infrastructure
#
# Phase 1: VPC + Security Groups + ECR + RDS (Aurora MySQL)
# Phase 2: EKS (AWS Console에서 수동 생성)!!
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

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  cluster_name         = var.cluster_name
  common_tags          = local.common_tags
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
  private_subnet_ids = module.vpc.private_subnet_ids
  db_password = module.secrets.db_password
  rds_sg_id          = module.security_groups.rds_sg_id
  database_name      = "oliveyoung"
  master_username    = "admin"
  # master_password는 random_password로 자동 생성 → ASM에 보관
  instance_class     = "db.t3.medium"
  common_tags        = local.common_tags
}
resource "aws_secretsmanager_secret" "db_secret" {
  name       = "${var.project_name}/db-password"
  kms_key_id = module.kms.rds_key_arn # <--- RDS 키 사용
  # 대기시간 없이 삭제
  recovery_window_in_days = 0
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
  # [변경 포인트]: RDS 엔드포인트를 실시간으로 받아서 Secret 값에 포함
  db_host         = module.rds.cluster_endpoint 
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
