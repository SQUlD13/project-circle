variable "project_name" {
  description = "Project name prefix for resource naming"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository in owner/repo format"
  type        = string
}

variable "ecr_repository" {
  description = "ECR repository name for push permissions"
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

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
