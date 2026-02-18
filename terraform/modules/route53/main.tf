################################################################################
# Route53 Module
# Hosted Zone만 생성 (레코드는 root에서 직접 관리)
# → ACM DNS 검증에 zone_id가 먼저 필요하므로 분리
################################################################################

# Hosted Zone (clmakase.click)
resource "aws_route53_zone" "this" {
  name    = var.domain_name
  # 기존의 호스팅 영역 사용 -> 테라폼에서 새로 만들면 ACM 과 꼬인다.
  comment = "HostedZone created by Route53 Registrar" 

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-zone"
  })
}
