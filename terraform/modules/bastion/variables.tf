################################################################################
# Bastion (CLI Server) Module - Variables
################################################################################

variable "vpc_id" {
  description = "VPC ID for bastion resources"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment (dev/staging/prod)"
  type        = string
}

variable "subnet_cidr" {
  description = "CIDR block for CLI server private subnet"
  type        = string
  default     = "10.0.3.0/24"
}

variable "availability_zone" {
  description = "Availability zone for CLI server subnet"
  type        = string
  default     = "ap-northeast-2a"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "ami_id" {
  description = "AMI ID for CLI server instance"
  type        = string
  default     = "ami-0dec6548c7c0d0a96"
}

variable "instance_type" {
  description = "EC2 instance type for CLI server"
  type        = string
  default     = "t3.micro"
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
