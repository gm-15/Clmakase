################################################################################
# RDS Module - Outputs
################################################################################

output "cluster_endpoint" {
  description = "Aurora cluster writer endpoint"
  value       = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  description = "Aurora cluster reader endpoint"
  value       = aws_rds_cluster.this.reader_endpoint
}

output "database_name" {
  description = "Database name"
  value       = aws_rds_cluster.this.database_name
}

output "port" {
  description = "Database port"
  value       = aws_rds_cluster.this.port
}

output "cluster_identifier" {
  description = "Aurora cluster identifier"
  value       = aws_rds_cluster.this.cluster_identifier
}
