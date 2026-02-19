################################################################################
# ElastiCache Module - Outputs
################################################################################

output "redis_endpoint" {
  description = "Redis primary endpoint"
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "redis_port" {
  description = "Redis port"
  value       = aws_elasticache_replication_group.this.port
}

output "redis_connection_url" {
  description = "Redis connection URL (spring.data.redis.host 형식)"
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}
