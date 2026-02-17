################################################################################
# Root Module - Variables
# CJ Oliveyoung CloudWave Infrastructure
################################################################################

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "cloudwave"
}

variable "environment" {
  description = "Environment"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability Zones"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "cloudwave-eks"
}

variable "ecr_repository_name" {
  description = "ECR repository name"
  type        = string
  default     = "oliveyoung-api"
}

## db_password 제거됨
## 비밀번호는 modules/rds에서 random_password로 자동 생성 → ASM에 보관

variable "domain_name" {
  description = "커스텀 도메인 이름 (Route53 + ACM + CloudFront)"
  type        = string
  default     = "clmakase.click"
}

variable "master_username" {
  description = "RDS 마스터 사용자 이름"
  type        = string
  default     = "admin"
}

variable "database_name" {
  description = "생성할 데이터베이스 이름"
  type        = string
  default     = "oliveyoung"
}
