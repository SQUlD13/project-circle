output "iam_role_arn" {
  description = "ARN of the IAM role for External Secrets Operator"
  value       = module.external_secrets_irsa.iam_role_arn
}

output "release_name" {
  description = "Name of the Helm release"
  value       = helm_release.external_secrets.name
}

output "namespace" {
  description = "Namespace where External Secrets is deployed"
  value       = helm_release.external_secrets.namespace
}
