################################################################################
# CloudFront Module
# OAC + CloudFront Distribution (S3 오리진 + ALB 오리진 + WAF 연동)
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

  # [연결 3] S3 오리진 (프론트엔드 정적 파일)
  origin {
    domain_name              = var.s3_bucket_domain_name
    origin_id                = "S3-${var.project_name}"
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  # [연결 4] ALB 오리진 (백엔드 API)
  # CloudFront → ALB 구간은 HTTP 사용 (ALB의 ssl-redirect 제거됨)
  # 사용자 → CloudFront 구간은 HTTPS 유지
  dynamic "origin" {
    for_each = var.alb_domain != "" ? [1] : []
    content {
      domain_name = var.alb_domain
      origin_id   = "ALB-${var.project_name}"

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "http-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  # [API 라우팅] /api/* → ALB 오리진 (캐시 비활성화, 모든 메서드 허용)
  dynamic "ordered_cache_behavior" {
    for_each = var.alb_domain != "" ? [1] : []
    content {
      path_pattern     = "/api/*"
      allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = "ALB-${var.project_name}"

      # CachingDisabled (API 응답 캐싱 안 함)
      cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"

      # AllViewerExceptHostHeader (Host 헤더 제외 모든 헤더/쿼리/쿠키 전달)
      origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"

      viewer_protocol_policy = "redirect-to-https"
    }
  }

  # [헬스체크 라우팅] /actuator/* → ALB 오리진
  dynamic "ordered_cache_behavior" {
    for_each = var.alb_domain != "" ? [1] : []
    content {
      path_pattern     = "/actuator/*"
      allowed_methods  = ["GET", "HEAD"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = "ALB-${var.project_name}"

      cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"

      viewer_protocol_policy = "redirect-to-https"
    }
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
