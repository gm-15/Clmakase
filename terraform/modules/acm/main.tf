################################################################################
# ACM Module (Existing Certificate Version)
################################################################################

# modules/acm/versions.tf (또는 main.tf 상단)

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      # 호출하는 쪽에서 aws.us_east_1을 넘겨줄 때
      # 모듈 내부에서 'aws'라는 이름으로 사용하겠다고 선언
      configuration_aliases = [ aws ]
    }
  }
}

# 1. ACM 인증서 요청
resource "aws_acm_certificate" "this" {
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-acm"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# 2. Route53에 DNS 검증 레코드 생성
resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = var.route53_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 300
  records = [each.value.record]

  allow_overwrite = true
}

# 3. 인증서 검증 완료 대기
resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}
