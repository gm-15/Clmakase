################################################################################
# CloudFront Module
# OAC + CloudFront Distribution (S3 오리진 + WAF 연동)
################################################################################

# 1. OAC 생성 (S3 접근 제어 장치)
resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "${var.project_name}-oac"
  description                       = "OAC for S3 Assets"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# 2. CloudFront 배포 설정
resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CDN for ${var.project_name}"
  default_root_object = "index.html"

  # [연결 1] 커스텀 도메인 (clmakase.click)
  aliases = var.domain_name != "" ? [var.domain_name] : []

  # [연결 2] WAF 결합
  web_acl_id = var.waf_acl_id

  # [연결 2] S3 오리진 설정
  origin {
    domain_name              = var.s3_bucket_domain_name
    origin_id                = "S3-${var.project_name}"
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${var.project_name}"

    # AWS 관리형 캐시 최적화 정책 (Managed-CachingOptimized)
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # 가격 계층 (PriceClass_100 = 북미+유럽, 가장 저렴)
  price_class = "PriceClass_100"

  # 지역 제한 설정
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # SSL/TLS 설정 (ACM 인증서 - us-east-1)
  viewer_certificate {
    acm_certificate_arn      = var.acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Name = "${var.project_name}-cdn"
  }
}
