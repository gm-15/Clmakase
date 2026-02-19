################################################################################
# ElastiCache Module - Variables
################################################################################

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment (dev/staging/prod)"
  type        = string
}

variable "node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.micro"
}

variable "num_cache_clusters" {
  description = "Number of cache clusters (nodes). 1 for dev, 2+ for prod"
  type        = number
  default     = 1
}

variable "engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.1"
}

variable "port" {
  description = "Redis port"
  type        = number
  default     = 6379
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for Redis placement"
  type        = list(string)
}

variable "redis_sg_id" {
  description = "Security group ID for Redis"
  type        = string
}

variable "snapshot_retention_limit" {
  description = "Number of days to retain snapshots. 0 to disable"
  type        = number
  default     = 0
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
