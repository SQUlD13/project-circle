locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  environment = local.env_vars.locals.environment
}

terraform {
  source = "${get_repo_root()}/terraform/modules/argocd"
}

dependency "eks" {
  config_path = "${get_terragrunt_dir()}/../eks"
  mock_outputs = {
    cluster_name      = "mock-cluster"
    cluster_endpoint  = "https://mock.eks.amazonaws.com"
    cluster_certificate_authority_data = "bW9jaw=="
  }
}

dependency "ingress_nginx" {
  config_path  = "${get_terragrunt_dir()}/../ingress-nginx"
  skip_outputs = true
}

generate "k8s_helm_provider" {
  path      = "k8s_helm_provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
data "aws_eks_cluster_auth" "cluster" {
  name = "${dependency.eks.outputs.cluster_name}"
}

provider "kubernetes" {
  host                   = "${dependency.eks.outputs.cluster_endpoint}"
  cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_certificate_authority_data}")
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = "${dependency.eks.outputs.cluster_endpoint}"
    cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_certificate_authority_data}")
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}
EOF
}

inputs = {
  cluster_name  = dependency.eks.outputs.cluster_name
  argocd_domain = "argocd-${local.environment}.project-circle.example.com"

  git_repo_url        = "git@github.com:SQUlD13/project-circle.git"
  git_ssh_private_key = file("${get_repo_root()}/.keys/argocd-deploy-key")

  tags = {
    Component = "argocd"
  }
}
