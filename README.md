# Project Circle

EKS infrastructure on AWS deployed with Terragrunt, using ArgoCD for GitOps delivery.

## Architecture

```
Internet → ALB → /dev/*     → dev namespace
                 /staging/* → staging namespace
                 /          → prod namespace
```

| Component | Role |
|---|---|
| EKS (v1.32) | Managed Kubernetes with IRSA |
| Terragrunt | DRY IaC with `_envcommon` pattern |
| ArgoCD | GitOps CD with SSH deploy key auth |
| AWS LB Controller | ALB ingress via IRSA |
| External Secrets | AWS Secrets Manager → K8s Secrets via IRSA |
| GitHub Actions | CI/CD with OIDC (no stored credentials) |

## Prerequisites

- AWS CLI v2, Terraform >= 1.5, Terragrunt >= 0.55
- kubectl, Helm 3, Docker
- GitHub CLI (`gh auth login`)

## Quick Start

```bash
# 1. Bootstrap (S3 state, DynamoDB locks, ECR, deploy key)
./scripts/setup.sh

# 2. Deploy infrastructure (~15-20 min)
cd terragrunt/dev/eu-west-1 && terragrunt run-all apply

# 3. Post-deploy (kubeconfig, OIDC secret, image push, ArgoCD apps)
./scripts/post-deploy.sh dev
```

## Teardown

```bash
./scripts/teardown.sh dev
```

## Customization

All project-wide config lives in `terragrunt/project.hcl`:

```hcl
locals {
  project_name   = "project-circle"
  aws_account_id = "530424100135"
  github_repo    = "SQUlD13/project-circle"
  git_repo_url   = "git@github.com:SQUlD13/project-circle.git"
  base_domain    = "project-circle.example.com"
}
```

## Project Structure

```
├── app/                          # Nginx app source
├── Dockerfile
├── scripts/
│   ├── setup.sh                  # Pre-deploy bootstrap
│   ├── post-deploy.sh            # Post-deploy automation
│   └── teardown.sh               # Clean destruction
├── terraform/modules/            # Terraform modules
│   ├── vpc/                      # VPC + subnets
│   ├── eks/                      # EKS cluster + node groups
│   ├── aws-load-balancer-controller/
│   ├── argocd/                   # ArgoCD + repo credentials
│   ├── external-secrets/         # ESO + IRSA + ClusterSecretStore
│   └── github-oidc/              # GitHub Actions OIDC role
├── terragrunt/
│   ├── project.hcl               # Project-wide config (source of truth)
│   ├── terragrunt.hcl            # Root config (backend, providers, tags)
│   ├── _envcommon/               # Shared module configs
│   └── dev/eu-west-1/            # Environment module instances
├── helm/generic-app/             # Helm chart + per-env value overrides
├── argocd/apps/                  # ArgoCD Application manifests
├── .secrets/                     # Secret values (gitignored, see below)
│   ├── dev/
│   │   └── app-config.json.example
│   ├── staging/
│   │   └── app-config.json.example
│   └── prod/
│       └── app-config.json.example
└── .github/workflows/ci.yaml    # CI pipeline
```

## Secrets Management

Application secrets are managed via AWS Secrets Manager with a three-phase flow:

**1. Infrastructure Setup (Terraform)**
- Creates empty secret shells in AWS Secrets Manager (e.g., `project-circle-dev/app/config`)
- IAM role grants pod access via ExternalSecrets Operator

**2. Secret Provisioning (`post-deploy.sh`)**
- Reads `.secrets/{namespace}/*.json` files from local disk
- Converts filenames: `app-config.json` → `app/config` (dashes become slashes)
- Pushes values to AWS Secrets Manager: `project-circle-{namespace}/{secret-path}`

**3. Application Sync (ExternalSecrets + Helm)**
- ExternalSecrets watches AWS Secrets Manager and creates Kubernetes Secrets
- Helm values define which keys each app expects: `externalSecret.data[i].property` (e.g., `example_secret`)
- App reads Kubernetes Secret mounted as volume

### Secret File Convention

Store secrets in `.secrets/{namespace}/` with JSON files matching the AWS Secrets Manager structure:

```bash
.secrets/
├── dev/
│   └── app-config.json           # Syncs to "project-circle-dev/app/config"
├── staging/
│   └── app-config.json           # Syncs to "project-circle-staging/app/config"
└── prod/
    └── app-config.json           # Syncs to "project-circle-prod/app/config"
```

**Filename Format:**
- Use lowercase, dash-separated names: `app-config.json` → path `app/config`
- Each JSON file contains keys the app expects (defined in Helm values)
- Example (`.secrets/dev/app-config.json`):
  ```json
  {
    "example_secret": "dev-value",
    "api_key": "dev-api-key-xyz"
  }
  ```

**Git Convention:**
- Commit `.json.example` files showing structure (gitignored example above)
- Actual `.json` files are gitignored (contain real values, never committed)
- On re-deploy, `post-deploy.sh` reads actual `.json` files and provisions to AWS

## ArgoCD UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:80
# password:
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## Cost (~$6/day for dev)

Tear down when not in use.
