#!/bin/bash
set -euo pipefail

# Project configuration (matches terragrunt/project.hcl)
# To use a different project, update both:
#   1. terragrunt/project.hcl (source of truth for Terraform)
#   2. scripts/setup.sh (this file - AWS bootstrapping)

PROJECT="project-circle"
ACCOUNT_ID="530424100135"
AWS_REGION="eu-west-1"
GITHUB_REPO="SQUlD13/project-circle"
BUCKET="${PROJECT}-terraform-state-${ACCOUNT_ID}"
TABLE="${PROJECT}-terraform-locks"

echo "=== Project Circle - Setup ==="
echo "Project: $PROJECT"
echo "Account: $ACCOUNT_ID"
echo "Region: $AWS_REGION"
echo "GitHub: $GITHUB_REPO"
echo ""

# Check prerequisites
for cmd in aws terraform terragrunt kubectl helm gh; do
  command -v $cmd >/dev/null 2>&1 || { echo "ERROR: $cmd not found"; exit 1; }
done
echo "[OK] All prerequisites found"

# Check AWS credentials
if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "ERROR: AWS credentials not configured or invalid"
  exit 1
fi
CURRENT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
if [ "$CURRENT_ACCOUNT" != "$ACCOUNT_ID" ]; then
  echo "ERROR: AWS account mismatch. Expected: $ACCOUNT_ID, Got: $CURRENT_ACCOUNT"
  exit 1
fi
echo "[OK] AWS credentials valid (account: $CURRENT_ACCOUNT)"

# Check GitHub CLI auth
if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: GitHub CLI not authenticated. Run: gh auth login"
  exit 1
fi
GITHUB_USER=$(gh api user --jq .login)
echo "[OK] GitHub CLI authenticated (user: $GITHUB_USER)"

# Generate ArgoCD deploy key if not present
KEYS_DIR="$(dirname "$0")/../.keys"
DEPLOY_KEY="$KEYS_DIR/argocd-deploy-key"

mkdir -p "$KEYS_DIR"

if [ ! -f "$DEPLOY_KEY" ]; then
  echo ""
  echo "Generating ArgoCD SSH deploy key..."
  ssh-keygen -t ed25519 -C "argocd-deploy-key" -f "$DEPLOY_KEY" -N "" >/dev/null 2>&1
  chmod 600 "$DEPLOY_KEY"
  chmod 644 "$DEPLOY_KEY.pub"
  echo "[OK] SSH deploy key generated at $DEPLOY_KEY"

  # Auto-upload deploy key to GitHub repo
  echo "Uploading deploy key to GitHub repo..."
  if gh repo deploy-key add "$DEPLOY_KEY.pub" --repo "$GITHUB_REPO" --title "ArgoCD Deploy Key" 2>/dev/null; then
    echo "[OK] Deploy key added to GitHub repo"
  else
    echo "[WARN] Could not auto-add deploy key (may already exist or insufficient permissions)"
    echo "[ACTION] Manually add this public key to GitHub repo (Settings > Deploy keys):"
    echo ""
    cat "$DEPLOY_KEY.pub"
    echo ""
  fi
else
  echo "[OK] SSH deploy key exists"
fi

# Create S3 state bucket
if ! aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  aws s3 mb "s3://$BUCKET" --region "$AWS_REGION"
  aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
  aws s3api put-bucket-encryption --bucket "$BUCKET" \
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
  echo "[OK] S3 bucket created"
else
  echo "[OK] S3 bucket exists"
fi

# Create DynamoDB lock table
if ! aws dynamodb describe-table --table-name "$TABLE" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws dynamodb create-table \
    --table-name "$TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$AWS_REGION"
  echo "[OK] DynamoDB table created"
else
  echo "[OK] DynamoDB table exists"
fi

# Create ECR repository
if ! aws ecr describe-repositories --repository-names "${PROJECT}-nginx" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws ecr create-repository \
    --repository-name "${PROJECT}-nginx" \
    --image-scanning-configuration scanOnPush=true \
    --region "$AWS_REGION"
  echo "[OK] ECR repository created"
else
  echo "[OK] ECR repository exists"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "1. Deploy infrastructure:"
echo "   cd terragrunt/dev/eu-west-1 && terragrunt run-all apply"
echo ""
echo "2. Run the post-deploy script (kubeconfig, OIDC secret, image push, ArgoCD apps):"
echo "   ./scripts/post-deploy.sh dev"
echo ""
