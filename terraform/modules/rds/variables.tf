################################################################################
# RDS Module - Variables
################################################################################

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

variable "private_subnet_ids" {
  description = "Private subnet IDs for DB subnet group"
  type        = list(string)
}

variable "rds_sg_id" {
  description = "RDS security group ID"
  type        = string
}

variable "database_name" {
  description = "Database name"
  type        = string
  default     = "oliveyoung"
}

variable "master_username" {
  description = "Master username"
  type        = string
  default     = "admin"
}

# 기존에 RDS 내부에 있던 KMS 관련 변수들은 이제 여기서 삭제해도 됩니다.
variable "db_password" {
  description = "랜덤 생성된 DB 비밀번호 (외부에서 주입)"
  type        = string
  sensitive   = true
}


variable "instance_class" {
  description = "Aurora instance class"
  type        = string
  default     = "db.t3.medium"
}

variable "common_tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
