################################################################################
# Bastion (CLI Server) Module - Outputs
################################################################################

output "instance_id" {
  description = "CLI server EC2 instance ID"
  value       = aws_instance.cli_server.id
}

output "private_ip" {
  description = "CLI server private IP address"
  value       = aws_instance.cli_server.private_ip
}

output "subnet_id" {
  description = "CLI server private subnet ID"
  value       = aws_subnet.cli_private_subnet.id
}
