################################################################################
# KMS Module - Outputs
################################################################################

output "s3_key_arn" {
  description = "S3/CloudFront용 KMS 키 ARN"
  value       = aws_kms_key.s3_key.arn
}

output "rds_key_arn" {
  description = "RDS/Secrets Manager용 KMS 키 ARN"
  value       = aws_kms_key.rds_key.arn
}

output "s3_key_id" {
  description = "S3/CloudFront용 KMS 키 ID"
  value       = aws_kms_key.s3_key.key_id
}

output "rds_key_id" {
  description = "RDS/Secrets Manager용 KMS 키 ID"
  value       = aws_kms_key.rds_key.key_id
}