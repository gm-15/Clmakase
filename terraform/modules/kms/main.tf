################################################################################
# KMS Module
# S3 + CloudFront 데이터 암호화용 마스터 키 & RDS 암호화 키
################################################################################

# 현재 AWS 계정 ID 자동 조회 (하드코딩 방지)
data "aws_caller_identity" "current" {}

# 1. S3/CloudFront 전용 KMS 마스터 키 생성
resource "aws_kms_key" "s3_key" {
  description             = var.description
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.s3_kms_policy.json

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-s3-kms"
  })
}

# 2. S3 키의 별칭(Alias) 생성
resource "aws_kms_alias" "s3_alias" {
  name          = "alias/${var.key_alias}"
  target_key_id = aws_kms_key.s3_key.key_id
}

# 3. RDS/ASM 전용 KMS 키 생성
resource "aws_kms_key" "rds_key" {
  description             = "KMS key for RDS Password and Cluster Encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.rds_kms_policy.json

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-rds-kms"
  })
}

# 4. RDS 키의 별칭(Alias) 생성
resource "aws_kms_alias" "rds_alias" {
  name          = "alias/${var.project_name}-rds-key"
  target_key_id = aws_kms_key.rds_key.key_id
}

################################################################################
# KMS 정책 정의 (Policy 분리)
################################################################################

# 5. S3/CloudFront 전용 정책 정의
data "aws_iam_policy_document" "s3_kms_policy" {
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

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
} # s3_kms_policy 블록 끝

# 6. RDS/Secrets Manager 전용 정책 정의
data "aws_iam_policy_document" "rds_kms_policy" {
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

  statement {
    sid    = "AllowRDSAndSecretsManagerToUseKey"
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = ["rds.amazonaws.com", "secretsmanager.amazonaws.com"]
    }
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
    resources = ["*"]
  }
} # rds_kms_policy 블록 끝