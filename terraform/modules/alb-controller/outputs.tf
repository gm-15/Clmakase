################################################################################
# ALB Controller Module - Outputs
################################################################################

output "alb_controller_role_arn" {
  description = "ALB Controller IRSA Role ARN"
  value       = aws_iam_role.alb_controller.arn
}
