output "iam_role_arn" {
  description = "ARN of the IAM role for AWS Load Balancer Controller"
  value       = module.aws_load_balancer_controller_irsa.iam_role_arn
}

output "release_name" {
  description = "Name of the Helm release"
  value       = helm_release.aws_load_balancer_controller.name
}
