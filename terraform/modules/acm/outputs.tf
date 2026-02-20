output "certificate_arn" {
  description = "ACM 인증서 ARN"
  value       = aws_acm_certificate.this.arn
}

output "certificate_domain" {
  description = "인증서 도메인"
  value       = aws_acm_certificate.this.domain_name
}
