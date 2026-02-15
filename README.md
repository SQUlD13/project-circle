# Project Circle - EKS Infrastructure

Kubernetes infrastructure on AWS EKS deployed with Terragrunt, using ArgoCD for GitOps delivery.

## Architecture

```
Internet → NLB (AWS LB Controller) → NGINX Ingress Controller → App Service → Pods
                                          ↓
                              Path routing: /dev/* → dev namespace
                                           /staging/* → staging namespace
                                           / → prod namespace
```

### Environments
| Environment | Cluster | Namespaces | Nodes |
|-------------|---------|------------|-------|
| Dev | project-circle-dev | dev, staging | 2-4 x t3.medium |
| Prod | project-circle-prod | prod | 3-6 x t3.large |

### Components
- **EKS** - Managed Kubernetes (v1.32) with IRSA enabled
- **Terragrunt** - DRY infrastructure-as-code with `_envcommon` pattern
- **ArgoCD** - GitOps continuous delivery with SSH deploy key autodiscovery
- **AWS Load Balancer Controller** - NLB provisioning via IRSA
- **NGINX Ingress Controller** - L7 application routing
- **External Secrets Operator** - AWS Secrets Manager → K8s Secrets via IRSA

### Dependency Chain
```
VPC → EKS → AWS LB Controller → Ingress NGINX → ArgoCD
              ↘ External Secrets
```

## Project Structure

```
├── app/                        # Nginx application source
│   ├── index.html
│   └── nginx.conf
├── Dockerfile
├── .keys/                      # SSH deploy keys (gitignored)
│   └── argocd-deploy-key       # ArgoCD → GitHub authentication
├── terraform/modules/          # Reusable Terraform modules
│   ├── vpc/                    # VPC with public/private subnets
│   ├── eks/                    # EKS cluster + managed node groups
│   ├── aws-load-balancer-controller/
│   ├── ingress-nginx/
│   ├── argocd/                 # Includes repo credential K8s Secret
│   └── external-secrets/       # Includes IRSA, ClusterSecretStore, SM secrets
├── terragrunt/                 # Live infrastructure configs
│   ├── terragrunt.hcl          # Root config (S3 backend, providers, default tags)
│   ├── _envcommon/             # Shared module configs (source, deps, inputs)
│   ├── dev/
│   │   ├── env.hcl             # Dev-specific values (instance types, sizes)
│   │   └── eu-west-1/          # Region-specific module instances
│   └── prod/
│       ├── env.hcl             # Prod-specific values
│       └── eu-west-1/
├── helm/generic-app/           # Generic Helm chart
│   ├── templates/              # Deployment, Service, Ingress, ExternalSecret
│   └── envs/                   # Per-environment value overrides
├── argocd/apps/                # ArgoCD Application manifests
│   ├── app-dev.yaml
│   ├── app-staging.yaml
│   └── app-prod.yaml
├── .github/workflows/ci.yaml  # CI pipeline
└── scripts/setup.sh           # Bootstrap script (S3, DynamoDB, ECR)
```

## Prerequisites

- AWS CLI v2 (configured with credentials for account `530424100135`, or update `terragrunt/project.hcl`)
- Terraform >= 1.5
- Terragrunt >= 0.55
- kubectl
- Helm 3
- GitHub CLI (`gh`) - authenticated via `gh auth login` for repo operations
- Docker - for building images locally

## Customizing for Your Environment

Edit `terragrunt/project.hcl` to customize project-wide values:

```hcl
locals {
  project_name   = "my-project"        # Change this
  aws_account_id = "123456789012"      # Change to your AWS account
  github_repo    = "myorg/my-project"  # Change to your GitHub repo
  git_repo_url   = "git@github.com:myorg/my-project.git"
}
```

These values are used everywhere:
- Terraform modules (via Terragrunt)
- Helm charts (global.projectName, global.awsAccountId)
- GitHub Actions (github_repo in OIDC trust policy)
- Resource naming (all resources prefixed with `${project_name}`)

## Getting Started

### 1. Generate ArgoCD Deploy Key

ArgoCD authenticates to this private repo using an SSH deploy key. Generate one if `.keys/argocd-deploy-key` doesn't exist:

```bash
mkdir -p .keys
ssh-keygen -t ed25519 -f .keys/argocd-deploy-key -N "" -C "argocd-deploy-key"
```

Add the public key to the GitHub repo as a read-only deploy key:

```bash
gh repo deploy-key add .keys/argocd-deploy-key.pub --title "argocd-deploy-key"
```

The `.keys/` directory is gitignored and never committed.

### 2. Bootstrap AWS Resources

```bash
chmod +x scripts/setup.sh
./scripts/setup.sh
```

Creates the S3 state bucket (versioned, encrypted), DynamoDB lock table, and ECR repository.

### 3. Deploy Infrastructure

```bash
cd terragrunt/dev/eu-west-1
terragrunt run-all apply
```

Terragrunt resolves the dependency graph and applies in order:
VPC → EKS → (AWS LB Controller + External Secrets) → Ingress NGINX → ArgoCD

Takes ~15-20 minutes on first run. ArgoCD automatically creates a K8s Secret with the deploy key for GitHub repo access (autodiscovery via `argocd.argoproj.io/secret-type: repository` label).

### 4. Configure kubectl

```bash
aws eks update-kubeconfig --name project-circle-dev --region eu-west-1
```

### 5. Deploy ArgoCD Applications

```bash
# Dev only
kubectl apply -f argocd/apps/app-dev.yaml

# All environments
kubectl apply -f argocd/apps/
```

ArgoCD clones the repo via SSH, renders the Helm chart with environment-specific values, and deploys to the target namespace.

### 6. Access ArgoCD UI

```bash
# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port forward
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open https://localhost:8080 (user: `admin`)

## ArgoCD — Git Integration

This project uses ArgoCD's **Secret autodiscovery** for repo authentication:

1. Terraform creates a K8s Secret in the `argocd` namespace with label `argocd.argoproj.io/secret-type: repository`
2. The Secret contains the SSH deploy key and repo URL
3. ArgoCD detects the label and auto-registers the repo credentials
4. GitHub's SSH host key is pre-configured in ArgoCD's Helm values (`configs.ssh.knownHosts`)

Application manifests in `argocd/apps/` define what to deploy:
- **source**: repo URL + Helm chart path + value files
- **destination**: target cluster + namespace
- **syncPolicy**: automated sync with prune and self-heal

## Secrets Flow

```
AWS Secrets Manager → External Secrets Operator (IRSA) → K8s Secret → Pod
```

1. Terraform creates secrets in AWS Secrets Manager (e.g., `project-circle-dev/app/config`)
2. `ClusterSecretStore` tells ESO how to authenticate (IRSA ServiceAccount)
3. `ExternalSecret` (deployed by ArgoCD via Helm) maps AWS secret properties to K8s Secret keys
4. ESO syncs automatically, refreshing every hour

## CI/CD Flow — GitHub Actions OIDC

1. Push to `main` triggers GitHub Actions (`.github/workflows/ci.yaml`)
2. GitHub Actions requests a signed JWT from `https://token.actions.githubusercontent.com`
3. Workflow calls `aws-actions/configure-aws-credentials@v4` with:
   - `role-to-assume`: `${{ secrets.AWS_ROLE_ARN }}` (stored in GitHub Secrets)
   - Role trust policy validates JWT claims (repo, branch, audience)
   - AWS STS returns temporary credentials (no long-lived secrets)
4. Docker image is built and pushed to ECR (tagged with commit SHA)
5. Image tag is updated in `helm/generic-app/envs/values-dev.yaml`
6. Commit is pushed, triggering ArgoCD sync
7. ArgoCD detects the change and syncs automatically

### Setting Up GitHub Actions OIDC

After deploying the `github-oidc` Terraform module, set the role ARN as a GitHub Secret:

```bash
# Get the role ARN from Terraform output
ROLE_ARN=$(cd terragrunt/dev/eu-west-1/github-oidc && terragrunt output -raw role_arn)

# Add to GitHub Secrets (requires gh CLI authenticated)
gh secret set AWS_ROLE_ARN --body "$ROLE_ARN"
```

This enables the CI workflow to authenticate to AWS **without storing long-lived credentials** in GitHub.

## Helm Chart

The generic chart (`helm/generic-app/`) deploys any containerized app with:
- Deployment (health probes, security context, read-only filesystem)
- Service (ClusterIP)
- Ingress (NGINX class, path-based routing with rewrite)
- ExternalSecret (AWS Secrets Manager)

```bash
# Template locally
helm template my-app helm/generic-app -f helm/generic-app/envs/values-dev.yaml

# Deploy directly (without ArgoCD)
helm install my-app helm/generic-app -n dev -f helm/generic-app/envs/values-dev.yaml
```

## Teardown

```bash
# Configuration (from terragrunt/project.hcl)
PROJECT="project-circle"
ACCOUNT_ID="530424100135"
AWS_REGION="eu-west-1"

# Delete ArgoCD applications first (cleans up managed resources)
kubectl delete -f argocd/apps/

# Destroy all infrastructure (reverse dependency order)
cd terragrunt/dev/eu-west-1
terragrunt run-all destroy

# Clean up bootstrap resources
BUCKET="${PROJECT}-terraform-state-${ACCOUNT_ID}"
TABLE="${PROJECT}-terraform-locks"

aws s3 rm "s3://${BUCKET}" --recursive
# Delete all object versions (required for versioned buckets)
aws s3api list-object-versions --bucket "$BUCKET" \
  --query 'Versions[].{Key:Key,VersionId:VersionId}' --output text | \
  while read key vid; do
    aws s3api delete-object --bucket "$BUCKET" \
      --key "$key" --version-id "$vid"
  done
aws s3 rb "s3://${BUCKET}"
aws dynamodb delete-table --table-name "$TABLE" --region "$AWS_REGION"
aws ecr delete-repository --repository-name "${PROJECT}-nginx" --region "$AWS_REGION" --force
```

## Cost Estimate (Dev)

| Resource | Hourly | Daily |
|---|---|---|
| EKS control plane | $0.10 | $2.40 |
| 2x t3.medium | $0.083 | $2.00 |
| NAT Gateway | $0.045 | $1.08 |
| NLB | $0.023 | $0.54 |
| **Total** | | **~$6/day** |

Tear down when not in use to avoid costs.
