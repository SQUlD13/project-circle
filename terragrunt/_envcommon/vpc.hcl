locals {
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))

  environment        = local.env_vars.locals.environment
  project_name       = local.project_vars.locals.project_name
  vpc_cidr           = local.env_vars.locals.vpc_cidr
  availability_zones = local.region_vars.locals.availability_zones
}

terraform {
  source = "${get_repo_root()}/terraform/modules/vpc"
}

inputs = {
  vpc_name           = "${local.project_name}-${local.environment}"
  vpc_cidr           = local.vpc_cidr
  availability_zones = local.availability_zones
  single_nat_gateway = local.environment == "dev" ? true : false

  public_subnets = [
    cidrsubnet(local.vpc_cidr, 4, 0),
    cidrsubnet(local.vpc_cidr, 4, 1),
    cidrsubnet(local.vpc_cidr, 4, 2),
  ]

  private_subnets = [
    cidrsubnet(local.vpc_cidr, 4, 3),
    cidrsubnet(local.vpc_cidr, 4, 4),
    cidrsubnet(local.vpc_cidr, 4, 5),
  ]

  cluster_name = "${local.project_name}-${local.environment}"
  environment  = local.environment

  tags = {
    Component = "networking"
  }
}
