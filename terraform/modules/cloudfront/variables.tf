################################################################################
# CloudFront Module - Variables
################################################################################

variable "project_name" {
  description = "프로젝트 이름"
  type        = string
}

variable "s3_bucket_domain_name" {
  description = "S3 버킷의 Regional Domain Name (오리진)"
  type        = string
}

variable "waf_acl_id" {
  description = "WAF 모듈에서 생성된 Web ACL ARN"
  type        = string
}

variable "domain_name" {
  description = "커스텀 도메인 (예: clmakase.click)"
  type        = string
  default     = ""
}

variable "acm_certificate_arn" {
  description = "ACM 인증서 ARN (us-east-1, CloudFront용)"
  type        = string
  default     = ""
}

variable "alb_domain" {
  description = "ALB DNS 이름 (kubectl get ingress -n oliveyoung 으로 확인)"
  type        = string
  default     = ""
}
