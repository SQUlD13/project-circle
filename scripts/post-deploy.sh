#!/bin/bash
set -euo pipefail

# Post-deploy script - run after 'terragrunt run-all apply' completes
# Handles: kubeconfig, OIDC secret, initial image push, ArgoCD app bootstrap

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT="project-circle"
ACCOUNT_ID="530424100135"
AWS_REGION="eu-west-1"
GITHUB_REPO="SQUlD13/project-circle"
ECR_REPO="${PROJECT}-nginx"
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}"
ENVIRONMENT="${1:-dev}"
CLUSTER_NAME="${PROJECT}-${ENVIRONMENT}"

echo "=== Project Circle - Post Deploy ==="
echo "Environment: $ENVIRONMENT"
echo "Cluster: $CLUSTER_NAME"
echo ""

# Check prerequisites
for cmd in aws kubectl helm gh docker; do
  command -v $cmd >/dev/null 2>&1 || { echo "ERROR: $cmd not found"; exit 1; }
done

# 1. Configure kubeconfig
echo "--- Configuring kubeconfig ---"
aws eks update-kubeconfig \
  --name "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --alias "$CLUSTER_NAME"
echo "[OK] kubeconfig updated for $CLUSTER_NAME"

# Wait for nodes to be ready
echo "Waiting for nodes to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s
echo "[OK] All nodes ready"

# 2. Clean up any Secrets Manager secrets scheduled for deletion (re-deploy safety)
echo ""
echo "--- Checking Secrets Manager ---"
SECRET_NAME="${CLUSTER_NAME}/app/config"
SECRET_STATUS=$(aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$AWS_REGION" --query 'DeletedDate' --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$SECRET_STATUS" != "None" ] && [ "$SECRET_STATUS" != "NOT_FOUND" ]; then
  echo "Secret '$SECRET_NAME' is scheduled for deletion, force-deleting..."
  aws secretsmanager delete-secret \
    --secret-id "$SECRET_NAME" \
    --force-delete-without-recovery \
    --region "$AWS_REGION" >/dev/null
  echo "[OK] Secret force-deleted (Terraform will recreate it)"
  sleep 5
else
  echo "[OK] No secret cleanup needed"
fi

# 3. Set GitHub Actions OIDC secret
echo ""
echo "--- Configuring GitHub Actions OIDC ---"
OIDC_DIR="$PROJECT_ROOT/terragrunt/$ENVIRONMENT/eu-west-1/github-oidc"
if [ -d "$OIDC_DIR" ]; then
  ROLE_ARN=$(cd "$OIDC_DIR" && terragrunt output -raw role_arn 2>/dev/null)
  if [ -n "$ROLE_ARN" ]; then
    gh secret set AWS_ROLE_ARN --repo "$GITHUB_REPO" --body "$ROLE_ARN"
    echo "[OK] AWS_ROLE_ARN secret set on GitHub repo ($ROLE_ARN)"
  else
    echo "[WARN] Could not read role_arn from github-oidc module"
  fi
else
  echo "[SKIP] github-oidc module not found at $OIDC_DIR"
fi

# 4. Build and push initial Docker image
echo ""
echo "--- Building and pushing initial Docker image ---"
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com" 2>/dev/null

# Check if any images exist in ECR
IMAGE_COUNT=$(aws ecr list-images --repository-name "$ECR_REPO" --region "$AWS_REGION" --query 'length(imageIds)' --output text 2>/dev/null || echo "0")
if [ "$IMAGE_COUNT" = "0" ]; then
  echo "No images in ECR, building and pushing initial image..."
  docker build -t "$ECR_URI:latest" \
    -t "$ECR_URI:dev-latest" \
    -t "$ECR_URI:staging-latest" \
    "$PROJECT_ROOT"
  docker push "$ECR_URI:latest"
  docker push "$ECR_URI:dev-latest"
  docker push "$ECR_URI:staging-latest"
  echo "[OK] Initial images pushed to ECR"
else
  echo "[OK] ECR already has $IMAGE_COUNT image(s), skipping build"
fi

# 5. Apply ArgoCD Application manifests
echo ""
echo "--- Bootstrapping ArgoCD Applications ---"
APPS_DIR="$PROJECT_ROOT/argocd/apps"

if [ -d "$APPS_DIR" ]; then
  # Only apply apps for the current environment
  if [ "$ENVIRONMENT" = "dev" ]; then
    # Dev cluster hosts both dev and staging
    for APP_FILE in "$APPS_DIR"/app-dev.yaml "$APPS_DIR"/app-staging.yaml; do
      if [ -f "$APP_FILE" ]; then
        kubectl apply -f "$APP_FILE"
        echo "[OK] Applied $(basename "$APP_FILE")"
      fi
    done
  elif [ "$ENVIRONMENT" = "prod" ]; then
    if [ -f "$APPS_DIR/app-prod.yaml" ]; then
      kubectl apply -f "$APPS_DIR/app-prod.yaml"
      echo "[OK] Applied app-prod.yaml"
    fi
  fi
else
  echo "[WARN] ArgoCD apps directory not found at $APPS_DIR"
fi

# 6. Wait for ArgoCD apps to sync
echo ""
echo "--- Waiting for ArgoCD sync ---"
echo "Waiting 30s for ArgoCD to reconcile..."
sleep 30

APPS=$(kubectl get applications -n argocd -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [ -n "$APPS" ]; then
  for APP in $APPS; do
    SYNC=$(kubectl get application "$APP" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    HEALTH=$(kubectl get application "$APP" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
    echo "  $APP: sync=$SYNC health=$HEALTH"
  done
else
  echo "[INFO] No ArgoCD applications found (may still be syncing)"
fi

# 7. Summary
echo ""
echo "=== Post Deploy Complete ==="
echo ""
echo "Cluster:  $CLUSTER_NAME"
echo "Region:   $AWS_REGION"

ALB=$(kubectl get ingress -A -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "provisioning")
echo "ALB:      $ALB"

echo ""
echo "Useful commands:"
echo "  kubectl get pods -A                    # Check all pods"
echo "  kubectl get applications -n argocd     # Check ArgoCD apps"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:80  # ArgoCD UI"
