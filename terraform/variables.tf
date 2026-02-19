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

variable "domain_name" {
  description = "커스텀 도메인 이름 (Route53 + ACM + CloudFront)"
  type        = string
  default     = "clmakase.click"
}

# --- EKS Node Group ---
variable "eks_node_instance_types" {
  description = "EKS 워커 노드 인스턴스 타입"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "eks_node_min_size" {
  description = "노드 그룹 최소 노드 수"
  type        = number
  default     = 2
}

variable "eks_node_desired_size" {
  description = "노드 그룹 현재(desired) 노드 수"
  type        = number
  default     = 3
}

variable "eks_node_max_size" {
  description = "노드 그룹 최대 노드 수"
  type        = number
  default     = 6
}

variable "eks_node_disk_size" {
  description = "노드 디스크 크기 (GB)"
  type        = number
  default     = 30
}

# --- ElastiCache ---
variable "redis_node_type" {
  description = "ElastiCache Redis 노드 타입"
  type        = string
  default     = "cache.t3.micro"
}
