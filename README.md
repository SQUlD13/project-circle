# Project Circle - EKS Infrastructure

Kubernetes infrastructure on AWS EKS deployed with Terragrunt, using ArgoCD for GitOps delivery.

## Architecture

```
Client → NLB (AWS LB Controller) → NGINX Ingress Controller → App Service → Pods
```

### Environments
| Environment | Cluster | Namespaces | Nodes |
|-------------|---------|------------|-------|
| Dev | project-circle-dev | dev, staging | 2-4 x t3.medium |
| Prod | project-circle-prod | prod | 3-6 x t3.large |

### Components
- **EKS** - Managed Kubernetes (v1.32)
- **Terragrunt** - DRY infrastructure-as-code
- **ArgoCD** - GitOps continuous delivery
- **AWS Load Balancer Controller** - NLB provisioning
- **NGINX Ingress Controller** - Application routing via NLB
- **External Secrets Operator** - AWS Secrets Manager integration

## Project Structure

```
├── app/                        # Nginx application source
│   ├── index.html
│   └── nginx.conf
├── Dockerfile
├── terraform/modules/          # Reusable Terraform modules
│   ├── vpc/                    # VPC with public/private subnets
│   ├── eks/                    # EKS cluster + managed node groups
│   ├── aws-load-balancer-controller/
│   ├── ingress-nginx/
│   ├── argocd/
│   └── external-secrets/
├── terragrunt/                 # Live infrastructure
│   ├── terragrunt.hcl          # Root config (remote state, providers)
│   ├── _envcommon/             # Shared module configs (DRY)
│   ├── dev/eu-west-1/          # Dev environment
│   └── prod/eu-west-1/         # Prod environment
├── helm/generic-app/           # Generic Helm chart
│   ├── templates/              # Deployment, Service, Ingress, ExternalSecret
│   └── envs/                   # Per-environment values
├── argocd/apps/                # ArgoCD Application manifests
│   ├── app-dev.yaml
│   ├── app-staging.yaml
│   └── app-prod.yaml
├── .github/workflows/ci.yaml  # CI/CD pipeline
└── scripts/setup.sh           # Bootstrap script
```

## Prerequisites

- AWS CLI v2 (configured with credentials)
- Terraform >= 1.5
- Terragrunt >= 0.55
- kubectl
- Helm 3

## Quick Start

### 1. Bootstrap AWS Resources
```bash
chmod +x scripts/setup.sh
./scripts/setup.sh
```
Creates the S3 state bucket, DynamoDB lock table, and ECR repository.

### 2. Deploy Infrastructure
```bash
cd terragrunt/dev/eu-west-1
terragrunt run-all apply
```

**Deployment order** (handled by Terragrunt dependencies):
1. VPC → 2. EKS → 3. AWS LB Controller → 4. Ingress NGINX → 5. ArgoCD → 6. External Secrets

### 3. Configure kubectl
```bash
aws eks update-kubeconfig --name project-circle-dev --region eu-west-1
```

### 4. Apply ArgoCD Applications
```bash
kubectl apply -f argocd/apps/
```

### 5. Access ArgoCD UI
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
Open https://localhost:8080 (user: `admin`)

## CI/CD Flow

1. Push to `main` triggers GitHub Actions
2. Docker image is built and pushed to ECR (tagged with commit SHA)
3. Image tag is updated in `values-dev.yaml` and `values-staging.yaml`
4. ArgoCD detects the change and syncs automatically

## Helm Chart

The generic chart deploys any containerized application with:
- Deployment (with health probes and security context)
- Service (ClusterIP)
- Ingress (NGINX class)
- ExternalSecret (AWS Secrets Manager)

```bash
# Template locally
helm template my-app helm/generic-app -f helm/generic-app/envs/values-dev.yaml

# Deploy directly (without ArgoCD)
helm install my-app helm/generic-app -n dev -f helm/generic-app/envs/values-dev.yaml
```

## Teardown

```bash
cd terragrunt/dev/eu-west-1
terragrunt run-all destroy
```
