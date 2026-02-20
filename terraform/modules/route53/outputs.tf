################################################################################
# Route53 Module - Outputs
################################################################################

output "zone_id" {
  description = "Route53 Hosted Zone ID"
  value       = data.aws_route53_zone.this.zone_id
}

output "name_servers" {
  description = "Route53 Name Servers (도메인 등록기관에 NS 설정 필요)"
  value       = data.aws_route53_zone.this.name_servers
}
