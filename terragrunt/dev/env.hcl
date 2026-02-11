locals {
  environment = "dev"
  vpc_cidr    = "10.0.0.0/16"

  eks_cluster_version = "1.32"
  node_groups = {
    general = {
      desired_size   = 2
      min_size       = 2
      max_size       = 4
      instance_types = ["t3.medium"]
    }
  }
}
