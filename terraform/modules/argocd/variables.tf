variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "argocd_domain" {
  description = "Domain for ArgoCD server"
  type        = string
}

variable "git_repo_url" {
  description = "SSH URL of the Git repository for ArgoCD"
  type        = string
  default     = ""
}

variable "git_ssh_private_key" {
  description = "SSH private key for ArgoCD to access the Git repository"
  type        = string
  sensitive   = true
  default     = ""
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
