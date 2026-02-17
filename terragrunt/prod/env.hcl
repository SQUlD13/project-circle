locals {
  environment = "prod"
  vpc_cidr    = "10.1.0.0/16"

  secrets = {
    prod = {
      "app/config" = jsonencode({ example_secret = "change-me-in-aws-console" })
    }
  }

  eks_cluster_version = "1.32"
  node_groups = {
    general = {
      desired_size   = 3
      min_size       = 3
      max_size       = 6
      instance_types = ["t3.large"]
    }
  }
}
