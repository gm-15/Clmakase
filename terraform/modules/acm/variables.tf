################################################################################
# ACM Module - Variables
################################################################################

variable "project_name" { type = string }
variable "domain_name"  { type = string }
variable "common_tags"  { type = map(string) }

# 검증 레코드를 만들지 않으므로 아래 변수는 모듈 내에서 사용되지 않습니다.
variable "route53_zone_id" {
  type    = string
  default = ""
}
