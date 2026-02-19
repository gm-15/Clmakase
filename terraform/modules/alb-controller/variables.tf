################################################################################
# ALB Controller Module - Variables
################################################################################

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment (dev/staging/prod)"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_oidc_provider_arn" {
  description = "EKS OIDC Provider ARN"
  type        = string
}

variable "cluster_oidc_provider_url" {
  description = "EKS OIDC Provider URL (https:// 제거됨)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "chart_version" {
  description = "ALB Controller Helm chart version"
  type        = string
  default     = "1.7.1"
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
