################################################################################
# Security Groups Module - Main
# CJ Oliveyoung EKS Infrastructure
#
# SG 구성:
#   1. EKS Control Plane SG - API Server 통신
#   2. EKS Node SG - 워커 노드 통신
#   3. ALB SG - 외부 HTTPS 트래픽
#   4. RDS SG - MySQL 접근
#   5. Redis SG - ElastiCache 접근
################################################################################

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ------------------------------------------------------------------------------
# 1. ALB Security Group
#    - 인터넷 → ALB (HTTPS 443, HTTP 80)
# ------------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name_prefix = "${local.name_prefix}-alb-"
  description = "Security group for Application Load Balancer"
  vpc_id      = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-alb-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from internet"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"

  tags = { Name = "alb-https-ingress" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from internet (redirect to HTTPS)"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"

  tags = { Name = "alb-http-ingress" }
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  description       = "All outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = { Name = "alb-all-egress" }
}

# ------------------------------------------------------------------------------
# 2. EKS Control Plane Security Group
#    - EKS API Server ↔ Worker Node 통신
# ------------------------------------------------------------------------------
resource "aws_security_group" "eks_control_plane" {
  name_prefix = "${local.name_prefix}-eks-cp-"
  description = "Security group for EKS Control Plane"
  vpc_id      = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-eks-cp-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "eks_cp_all" {
  security_group_id = aws_security_group.eks_control_plane.id
  description       = "All outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = { Name = "eks-cp-all-egress" }
}

# ------------------------------------------------------------------------------
# 3. EKS Node Security Group
#    - 워커 노드 간 통신, Control Plane 통신, ALB 트래픽 수신
# ------------------------------------------------------------------------------
resource "aws_security_group" "eks_node" {
  name_prefix = "${local.name_prefix}-eks-node-"
  description = "Security group for EKS Worker Nodes"
  vpc_id      = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-eks-node-sg"
    "karpenter.sh/discovery" = var.cluster_name
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Node ↔ Node: 노드 간 모든 통신 허용
resource "aws_vpc_security_group_ingress_rule" "node_self" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "Node to node communication"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.eks_node.id

  tags = { Name = "node-self-ingress" }
}

# Control Plane → Node: kubelet, kube-proxy (443, 10250)
resource "aws_vpc_security_group_ingress_rule" "node_from_cp_https" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "Control plane to node (HTTPS)"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.eks_control_plane.id

  tags = { Name = "node-from-cp-https" }
}

resource "aws_vpc_security_group_ingress_rule" "node_from_cp_kubelet" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "Control plane to kubelet"
  from_port                    = 10250
  to_port                      = 10250
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.eks_control_plane.id

  tags = { Name = "node-from-cp-kubelet" }
}

# Control Plane → Node: CoreDNS (TCP/UDP 53)
resource "aws_vpc_security_group_ingress_rule" "node_from_cp_dns_tcp" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "Control plane to CoreDNS (TCP)"
  from_port                    = 53
  to_port                      = 53
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.eks_control_plane.id

  tags = { Name = "node-from-cp-dns-tcp" }
}

resource "aws_vpc_security_group_ingress_rule" "node_from_cp_dns_udp" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "Control plane to CoreDNS (UDP)"
  from_port                    = 53
  to_port                      = 53
  ip_protocol                  = "udp"
  referenced_security_group_id = aws_security_group.eks_control_plane.id

  tags = { Name = "node-from-cp-dns-udp" }
}

# ALB → Node: 앱 트래픽 (NodePort 범위)
resource "aws_vpc_security_group_ingress_rule" "node_from_alb" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "ALB to node (NodePort range)"
  from_port                    = 30000
  to_port                      = 32767
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.alb.id

  tags = { Name = "node-from-alb-nodeport" }
}

# ALB → Node: target type=ip일 경우 앱 포트 직접 접근
resource "aws_vpc_security_group_ingress_rule" "node_from_alb_app" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "ALB to node (app port 8080)"
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.alb.id

  tags = { Name = "node-from-alb-app" }
}

resource "aws_vpc_security_group_egress_rule" "node_all" {
  security_group_id = aws_security_group.eks_node.id
  description       = "All outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = { Name = "node-all-egress" }
}

# Node → Control Plane: API Server 통신
resource "aws_vpc_security_group_ingress_rule" "cp_from_node" {
  security_group_id            = aws_security_group.eks_control_plane.id
  description                  = "Node to control plane API"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.eks_node.id

  tags = { Name = "cp-from-node" }
}

# ------------------------------------------------------------------------------
# 4. RDS Security Group
#    - EKS Node → RDS (MySQL 3306)
# ------------------------------------------------------------------------------
resource "aws_security_group" "rds" {
  name_prefix = "${local.name_prefix}-rds-"
  description = "Security group for RDS MySQL"
  vpc_id      = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-rds-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_node" {
  security_group_id            = aws_security_group.rds.id
  description                  = "EKS nodes to RDS MySQL"
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.eks_node.id

  tags = { Name = "rds-from-eks-node" }
}

resource "aws_vpc_security_group_egress_rule" "rds_all" {
  security_group_id = aws_security_group.rds.id
  description       = "All outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = { Name = "rds-all-egress" }
}

# ------------------------------------------------------------------------------
# 5. Redis (ElastiCache) Security Group
#    - EKS Node → Redis (6379)
# ------------------------------------------------------------------------------
resource "aws_security_group" "redis" {
  name_prefix = "${local.name_prefix}-redis-"
  description = "Security group for ElastiCache Redis"
  vpc_id      = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-redis-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_node" {
  security_group_id            = aws_security_group.redis.id
  description                  = "EKS nodes to Redis"
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.eks_node.id

  tags = { Name = "redis-from-eks-node" }
}

resource "aws_vpc_security_group_egress_rule" "redis_all" {
  security_group_id = aws_security_group.redis.id
  description       = "All outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = { Name = "redis-all-egress" }
}
