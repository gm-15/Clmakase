################################################################################
# Root Module - Outputs
# AWS Console에서 EKS 생성 시 필요한 값들
################################################################################

# --- VPC ---
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs (EKS 노드 배치)"
  value       = module.vpc.private_subnet_ids
}

# --- Security Groups ---
output "eks_control_plane_sg_id" {
  description = "EKS Control Plane SG ID"
  value       = module.security_groups.eks_control_plane_sg_id
}

output "eks_node_sg_id" {
  description = "EKS Node SG ID"
  value       = module.security_groups.eks_node_sg_id
}

output "alb_sg_id" {
  description = "ALB SG ID"
  value       = module.security_groups.alb_sg_id
}

output "rds_sg_id" {
  description = "RDS SG ID"
  value       = module.security_groups.rds_sg_id
}

output "redis_sg_id" {
  description = "Redis SG ID"
  value       = module.security_groups.redis_sg_id
}

# --- ECR ---
output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = module.ecr.repository_url
}

output "ecr_repository_name" {
  description = "ECR repository name"
  value       = module.ecr.repository_name
}

# --- RDS (Aurora MySQL) ---
output "rds_cluster_endpoint" {
  description = "Aurora MySQL Writer Endpoint"
  value       = module.rds.cluster_endpoint
}

output "rds_reader_endpoint" {
  description = "Aurora MySQL Reader Endpoint"
  value       = module.rds.reader_endpoint
}

output "rds_database_name" {
  description = "Database name"
  value       = module.rds.database_name
}

# --- KMS ---
output "rds_kms_key_arn" {
  description = "RDS/Secrets Manager용 KMS 키 ARN"
  value       = module.kms.rds_key_arn
}

# --- ASM (Secrets Manager) ---
output "rds_secret_arn" {
  description = "Secrets Manager ARN (DB 비밀번호)"
  value       = module.secrets.secret_arn
}

output "rds_secret_name" {
  description = "Secrets Manager Name (DB 비밀번호)"
  value       = module.secrets.secret_name
}

# --- WAF ---
output "waf_web_acl_arn" {
  description = "WAF Web ACL ARN (CloudFront 연동용)"
  value       = module.waf.web_acl_arn
}

output "waf_web_acl_id" {
  description = "WAF Web ACL ID"
  value       = module.waf.web_acl_id
}

# --- KMS ---
output "s3_kms_key_arn" {
  description = "KMS 키 ARN (S3 암호화용)"
  value       = module.kms.s3_key_arn
}

output "kms_key_id" {
  description = "KMS 키 ID"
  value       = module.kms.s3_key_id
}

# --- S3 ---
output "s3_bucket_id" {
  description = "S3 정적 자산 버킷 ID"
  value       = module.s3.bucket_id
}

output "s3_bucket_domain_name" {
  description = "S3 Regional Domain Name"
  value       = module.s3.bucket_regional_domain_name
}

# --- CloudFront ---
output "cloudfront_domain_name" {
  description = "CloudFront 배포 도메인 (Route53 연동용)"
  value       = module.cloudfront.cloudfront_domain_name
}

output "cloudfront_arn" {
  description = "CloudFront 배포 ARN"
  value       = module.cloudfront.cloudfront_arn
}

output "cloudfront_distribution_id" {
  description = "CloudFront Distribution ID"
  value       = module.cloudfront.cloudfront_distribution_id
}

# --- Route53 ---
output "route53_zone_id" {
  description = "Route53 Hosted Zone ID"
  value       = module.route53.zone_id
}

output "route53_name_servers" {
  description = "Route53 Name Servers (도메인 등록기관 NS 설정 확인용)"
  value       = module.route53.name_servers
}

# --- ACM ---
output "acm_certificate_arn_cloudfront" {
  description = "ACM SSL 인증서 ARN (us-east-1)"
  value       = module.acm_cloudfront.certificate_arn
}
output "acm_certificate_arn_alb" {
  description = "ALB용 ACM 인증서 ARN (ap-northeast-2)"
  value       = module.acm_alb.certificate_arn
}

# --- EKS ---
output "eks_cluster_endpoint" {
  description = "EKS Cluster API Endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_name" {
  description = "EKS Cluster Name"
  value       = module.eks.cluster_name
}

output "eks_cluster_version" {
  description = "EKS Kubernetes Version"
  value       = module.eks.cluster_version
}

output "eks_oidc_provider_arn" {
  description = "EKS OIDC Provider ARN (IRSA용)"
  value       = module.eks.oidc_provider_arn
}

output "eks_node_group_role_arn" {
  description = "EKS Node Group IAM Role ARN"
  value       = module.eks.node_group_role_arn
}

# --- ElastiCache (Redis) ---
output "redis_endpoint" {
  description = "ElastiCache Redis Primary Endpoint"
  value       = module.elasticache.redis_endpoint
}

output "redis_port" {
  description = "ElastiCache Redis Port"
  value       = module.elasticache.redis_port
}

# --- ALB Controller ---
output "alb_controller_role_arn" {
  description = "ALB Controller IRSA Role ARN"
  value       = module.alb_controller.alb_controller_role_arn
}

# --- ArgoCD ---
output "argocd_namespace" {
  description = "ArgoCD Namespace"
  value       = module.argocd.argocd_namespace
}

# --- kubectl 설정 명령어 ---
output "kubectl_config_command" {
  description = "kubectl 설정 명령어"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}
