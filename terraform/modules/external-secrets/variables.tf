variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider for IRSA"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "project_name" {
  description = "Project name used as prefix for secret names in AWS Secrets Manager"
  type        = string
}

variable "secrets" {
  description = "Namespace-keyed secret paths: namespace → list of secret paths to create in AWS Secrets Manager"
  type        = map(list(string))
  default     = {}
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
