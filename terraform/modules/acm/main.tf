################################################################################
# ACM Module (Existing Certificate Version)
################################################################################

# 상위(Root)에서 넘겨주는 aws.us_east_1 프로바이더를 받을 준비.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# 1. 이미 발급된 인증서 정보를 가져옵니다.
data "aws_acm_certificate" "this" {
  domain      = var.domain_name
  statuses    = ["ISSUED"]
  most_recent = true
}
