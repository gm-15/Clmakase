################################################################################
# Security Groups Module - Outputs
################################################################################

output "alb_sg_id" {
  description = "ALB security group ID"
  value       = aws_security_group.alb.id
}

output "eks_control_plane_sg_id" {
  description = "EKS Control Plane security group ID"
  value       = aws_security_group.eks_control_plane.id
}

output "eks_node_sg_id" {
  description = "EKS Worker Node security group ID"
  value       = aws_security_group.eks_node.id
}

output "rds_sg_id" {
  description = "RDS security group ID"
  value       = aws_security_group.rds.id
}

output "redis_sg_id" {
  description = "Redis security group ID"
  value       = aws_security_group.redis.id
}

output "bastion_cli_sg_id" {
  description = "Bastion CLI server security group ID"
  value       = aws_security_group.bastion_cli.id
}

output "bastion_vpce_sg_id" {
  description = "Bastion VPC Endpoint security group ID"
  value       = aws_security_group.bastion_vpce.id
}
