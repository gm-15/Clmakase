output "db_password" {
  description = "생성된 랜덤 비밀번호"
  value       = random_password.db_password.result
  sensitive   = true
}

output "secret_arn" {
  description = "Secrets Manager ARN"
  value       = aws_secretsmanager_secret.this.arn
}

output "secret_name" {
  description = "Secrets Manager 이름"
  value       = aws_secretsmanager_secret.this.name
}