################################################################################
# Secrets Module - AWS Secrets Manager
################################################################################

# 1. DB용 랜덤 비밀번호 생성
resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# 2. AWS Secrets Manager (ASM) 생성
resource "aws_secretsmanager_secret" "this" {
  name        = "${var.project_name}/${var.environment}/db-password"
  description = "Aurora MySQL password encrypted with RDS KMS Key"
  kms_key_id  = var.kms_key_arn

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-db-secret"
  })
}

# 3. 비밀번호 값 저장 (JSON)
resource "aws_secretsmanager_secret_version" "this" {
  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.db_password.result
    host     = var.db_host
    port     = 3306
    dbname   = var.database_name
  })
}