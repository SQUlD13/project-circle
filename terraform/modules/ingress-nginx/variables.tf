variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "load_balancer_scheme" {
  description = "Load balancer scheme: internet-facing or internal"
  type        = string
  default     = "internet-facing"
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
