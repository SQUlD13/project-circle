locals {
  env_vars    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))
}

terraform {
  source = "${get_repo_root()}/terraform/modules/github-oidc"
}

inputs = {
  project_name   = "project-circle"
  github_repo    = "SQUlD13/project-circle"
  ecr_repository = "project-circle-nginx"
  region         = local.region_vars.locals.aws_region
  aws_account_id = "530424100135"

  tags = {
    Component = "github-oidc"
  }
}
