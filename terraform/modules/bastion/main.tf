################################################################################
# Bastion (CLI Server) Module - Main
################################################################################

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# 1. CLI 서버용 프라이빗 서브넷 생성
resource "aws_subnet" "cli_private_subnet" {
  vpc_id            = var.vpc_id
  cidr_block        = var.subnet_cidr
  availability_zone = var.availability_zone

  tags = { Name = "${local.name_prefix}-cli-private-subnet" }
}

# 2. 프라이빗 전용 라우팅 테이블 생성
resource "aws_route_table" "private_rt" {
  vpc_id = var.vpc_id

  tags = { Name = "${local.name_prefix}-cli-private-rt" }
}

# 3. 서브넷과 라우팅 테이블 연결 (이 작업이 있어야 서브넷이 이 규칙을 따름)
resource "aws_route_table_association" "private_rt_assign" {
  subnet_id      = aws_subnet.cli_private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

# 4. S3 Gateway Endpoint (패키지 설치용)
resource "aws_vpc_endpoint" "s3_gw" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  # 위에서 만든 라우팅 테이블 ID를 참조합니다.
  # 이렇게 하면 라우팅 테이블에 S3행 경로가 자동으로 추가됩니다.
  route_table_ids = [aws_route_table.private_rt.id]

  tags = { Name = "${local.name_prefix}-s3-gateway-endpoint" }
}

# 5. IAM Instance Profile (SSM 권한)
resource "aws_iam_role" "cli_role" {
  name = "${local.name_prefix}-cli-server-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17", Statement = [{
      Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.cli_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "cli_profile" {
  name = "${local.name_prefix}-cli-instance-profile"
  role = aws_iam_role.cli_role.name
}

# 6. SSM Interface Endpoints
resource "aws_vpc_endpoint" "ssm_endpoints" {
  for_each = toset(["ssm", "ssmmessages", "ec2messages"])
  vpc_id   = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.cli_private_subnet.id]
  security_group_ids  = [var.vpce_sg_id]
  private_dns_enabled = true
}

# 7. CLI 서버 인스턴스
resource "aws_instance" "cli_server" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.cli_private_subnet.id
  vpc_security_group_ids = [var.cli_sg_id]
  iam_instance_profile   = aws_iam_instance_profile.cli_profile.name

  tags = { Name = "${local.name_prefix}-private-cli-server" }
}
