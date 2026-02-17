################################################################################
# KMS Module
# S3 + CloudFront 데이터 암호화용 마스터 키
################################################################################

# 현재 AWS 계정 ID 자동 조회 (하드코딩 방지)
data "aws_caller_identity" "current" {}

# 1. KMS 마스터 키 생성
resource "aws_kms_key" "this" {
  description             = var.description
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = data.aws_iam_policy_document.kms_policy.json

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-kms"
  })
}

# 2. 키의 별칭(Alias) 생성
resource "aws_kms_alias" "this" {
  name          = "alias/${var.key_alias}"
  target_key_id = aws_kms_key.this.key_id
}

# 3. KMS 키 정책 정의
data "aws_iam_policy_document" "kms_policy" {
  # (A) 관리자 권한 (루트 계정에 모든 권한 부여)
  statement {
    sid    = "EnableIAMUserPermissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  # (B) S3 및 CloudFront 서비스 권한: 데이터 암복호화용
  statement {
    sid    = "AllowS3AndCloudFrontToUseKey"
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = [
        "s3.amazonaws.com",
        "cloudfront.amazonaws.com"
      ]
    }
    actions = [
      "kms:GenerateDataKey*",
      "kms:Decrypt"
    ]
    resources = ["*"]

    # 이 부분이 핵심입니다! 특정 계정의 자원만 허용
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}
