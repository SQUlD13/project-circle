locals {
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
}

terraform {
  source = "${get_repo_root()}/terraform/modules/github-oidc"
}

inputs = {
  project_name   = local.project_vars.locals.project_name
  github_repo    = local.project_vars.locals.github_repo
  ecr_repository = "${local.project_vars.locals.project_name}-nginx"
  region         = local.region_vars.locals.aws_region
  aws_account_id = local.project_vars.locals.aws_account_id

  tags = {
    Component = "github-oidc"
  }
}
