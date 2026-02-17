################################################################################
# RDS Module - Aurora MySQL + ASM (Secrets Manager)
# CJ Oliveyoung CloudWave Infrastructure
#
# Private Subnet에 Aurora MySQL 클러스터 생성
# EKS 워커 노드에서만 접근 가능 (RDS SG)
# DB 비밀번호는 random_password로 자동 생성 → ASM + KMS로 안전하게 보관
################################################################################

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ------------------------------------------------------------------------------
# DB Subnet Group
# Aurora 클러스터를 배치할 서브넷 그룹 (Private Subnet 2개, Multi-AZ)
# ------------------------------------------------------------------------------
resource "aws_db_subnet_group" "this" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-db-subnet-group"
  })
}

# ------------------------------------------------------------------------------
# Aurora MySQL Cluster
# ------------------------------------------------------------------------------
resource "aws_rds_cluster" "this" {
  cluster_identifier = "${local.name_prefix}-aurora"
  engine             = "aurora-mysql"
  engine_version     = "8.0.mysql_aurora.3.04.6"

  database_name   = var.database_name
  master_username = var.master_username
  # 비밀번호는 이제 외부 변수에서 주입받습니다.
  master_password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.rds_sg_id]

  # Dev 환경 설정
  skip_final_snapshot = true
  deletion_protection = false

  # 백업
  backup_retention_period = 1
  preferred_backup_window = "03:00-04:00"

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-aurora-cluster"
  })
}

# ------------------------------------------------------------------------------
# Aurora MySQL Instance (Writer)
# ------------------------------------------------------------------------------
resource "aws_rds_cluster_instance" "writer" {
  identifier         = "${local.name_prefix}-aurora-writer"
  cluster_identifier = aws_rds_cluster.this.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version

  db_subnet_group_name = aws_db_subnet_group.this.name

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-aurora-writer"
  })
}
