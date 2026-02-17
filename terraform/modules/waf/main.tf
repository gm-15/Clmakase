################################################################################
# WAF Module - AWS WAF v2
# CJ Oliveyoung CloudWave Infrastructure
#
# CloudFront 연동용 WAF (scope: CLOUDFRONT → us-east-1 필수)
# AI 기반 Managed Rules로 DDoS, 봇, SQLi/XSS 등 자동 차단
################################################################################

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      # 버전은 루트 모듈과 맞추는 것이 좋습니다.
      version = "~> 5.0" 
    }
  }
}

resource "aws_wafv2_web_acl" "main" {
  name        = "${var.project_name}-waf"
  description = "Advanced Managed Rules for CloudFront with DDoS & Bot Protection"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # 우선순위 0: L7 DDoS 방어
  rule {
    name     = "AWS-AWSManagedRulesAntiDDoSRuleSet"
    priority = 0
    override_action {
      none {} 
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAntiDDoSRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AntiDDoS"
      sampled_requests_enabled   = true
    }
  }

  # 우선순위 1: Amazon IP 평판 목록 (AI 위협 인텔리전스)
  rule {
    name     = "AWS-AWSManagedRulesAmazonIpReputationList"
    priority = 1
    override_action {
      none {} 
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AmazonIpReputation"
      sampled_requests_enabled   = true
    }
  }

  # 우선순위 2: 익명 IP 차단 (VPN/Tor)
  rule {
    name     = "AWS-AWSManagedRulesAnonymousIpList"
    priority = 2
    override_action {
      none {}  
    }
       
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAnonymousIpList"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AnonymousIP"
      sampled_requests_enabled   = true
    }
  }

  # 우선순위 3: 공통 규칙 세트 (SQLi, XSS 등)
  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 3
    override_action {
      none {} 
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRules"
      sampled_requests_enabled   = true
    }
  }

  # 우선순위 4: 봇 컨트롤 (AI 기반 봇 탐지)
  rule {
    name     = "AWS-AWSManagedRulesBotControlRuleSet"
    priority = 4
    override_action {
      none {} 
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesBotControlRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BotControl"
      sampled_requests_enabled   = true
    }
  }

  # 우선순위 5: 속도 제한 + 캡차 (IP당 5분간 2000 요청 초과 시)
  rule {
    name     = "RateLimitWithCaptcha"
    priority = 5
    action {
      captcha {}
    }
    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitCaptcha"
      sampled_requests_enabled   = true
    }
  }

  # 우선순위 6: EKS(Linux) 보호
  rule {
    name     = "AWS-AWSManagedRulesLinuxRuleSet"
    priority = 6
    override_action {
      none {} 
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesLinuxRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "LinuxRules"
      sampled_requests_enabled   = true
    }
  }

  # 우선순위 7: EKS(POSIX/Unix) 보호
  rule {
    name     = "AWS-AWSManagedRulesUnixRuleSet"
    priority = 7
    override_action {
      none {} 
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesUnixRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "UnixRules"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf-main"
    sampled_requests_enabled   = true
  }

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-waf"
  })
}
