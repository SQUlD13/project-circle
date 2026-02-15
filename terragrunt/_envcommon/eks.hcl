locals {
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))

  environment     = local.env_vars.locals.environment
  project_name    = local.project_vars.locals.project_name
  cluster_version = local.env_vars.locals.eks_cluster_version
  node_groups     = local.env_vars.locals.node_groups
}

terraform {
  source = "${get_repo_root()}/terraform/modules/eks"
}

dependency "vpc" {
  config_path = "${get_terragrunt_dir()}/../vpc"

  mock_outputs = {
    vpc_id          = "vpc-00000000"
    private_subnets = ["subnet-00000000", "subnet-11111111", "subnet-22222222"]
  }
}

inputs = {
  cluster_name    = "${local.project_name}-${local.environment}"
  cluster_version = local.cluster_version
  vpc_id          = dependency.vpc.outputs.vpc_id
  private_subnets = dependency.vpc.outputs.private_subnets

  node_groups = {
    for name, config in local.node_groups : name => merge(config, {
      subnet_ids = dependency.vpc.outputs.private_subnets
      labels = {
        Environment = local.environment
        NodeGroup   = name
      }
    })
  }

  tags = {
    Component = "kubernetes"
  }
}
