################################################################################
# ElastiCache Module - Main
# CJ Oliveyoung CloudWave Infrastructure
#
# Creates: Redis Replication Group + Subnet Group
# - 대기열 관리 및 캐시용 ElastiCache Redis
# - Private 서브넷에 배치, EKS 노드에서만 접근 가능
################################################################################

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ------------------------------------------------------------------------------
# ElastiCache Subnet Group
# - Private 서브넷에 Redis 배치
# ------------------------------------------------------------------------------
resource "aws_elasticache_subnet_group" "this" {
  name       = "${local.name_prefix}-redis-subnet"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-redis-subnet-group"
  })
}

# ------------------------------------------------------------------------------
# ElastiCache Replication Group (Redis)
# - dev: 단일 노드, automatic_failover 비활성화
# - prod: 2+ 노드로 변경 시 automatic_failover 활성화
# ------------------------------------------------------------------------------
resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${local.name_prefix}-redis"
  description          = "${var.project_name} Redis for queue and cache"

  engine               = "redis"
  engine_version       = var.engine_version
  node_type            = var.node_type
  num_cache_clusters   = var.num_cache_clusters
  port                 = var.port
  parameter_group_name = "default.redis7"

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [var.redis_sg_id]

  # 고가용성 설정
  automatic_failover_enabled = var.num_cache_clusters > 1 ? true : false
  multi_az_enabled           = var.num_cache_clusters > 1 ? true : false

  # 보안 설정
  at_rest_encryption_enabled = true
  transit_encryption_enabled = false # 앱 코드가 TLS 미사용

  # 백업 설정 (dev: 비활성화)
  snapshot_retention_limit = var.snapshot_retention_limit

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-redis"
  })
}
