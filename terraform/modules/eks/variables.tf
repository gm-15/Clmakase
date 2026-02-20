################################################################################
# EKS Module - Variables
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

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.29"
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for EKS"
  type        = list(string)
}

variable "control_plane_sg_id" {
  description = "Security group ID for EKS control plane"
  type        = string
}

variable "node_sg_id" {
  description = "Security group ID for EKS worker nodes"
  type        = string
}

# Node instance/scaling 변수 제거 - Karpenter NodePool에서 관리

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
