#!/bin/bash
set -euo pipefail

# Teardown script - cleanly destroys infrastructure for an environment
# Usage: ./scripts/teardown.sh [dev|prod]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT="project-circle"
AWS_REGION="eu-west-1"
ENVIRONMENT="${1:-dev}"
CLUSTER_NAME="${PROJECT}-${ENVIRONMENT}"

echo "=== Project Circle - Teardown ==="
echo "Environment: $ENVIRONMENT"
echo "Cluster: $CLUSTER_NAME"
echo ""

read -p "Are you sure you want to destroy the $ENVIRONMENT environment? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

# 1. Remove ArgoCD applications (lets ArgoCD clean up managed resources)
echo ""
echo "--- Removing ArgoCD Applications ---"
if kubectl get applications -n argocd >/dev/null 2>&1; then
  APPS_DIR="$PROJECT_ROOT/argocd/apps"
  if [ "$ENVIRONMENT" = "dev" ]; then
    for APP_FILE in "$APPS_DIR"/app-dev.yaml "$APPS_DIR"/app-staging.yaml; do
      if [ -f "$APP_FILE" ]; then
        kubectl delete -f "$APP_FILE" --ignore-not-found=true 2>/dev/null || true
        echo "[OK] Deleted $(basename "$APP_FILE")"
      fi
    done
  elif [ "$ENVIRONMENT" = "prod" ]; then
    if [ -f "$APPS_DIR/app-prod.yaml" ]; then
      kubectl delete -f "$APPS_DIR/app-prod.yaml" --ignore-not-found=true 2>/dev/null || true
      echo "[OK] Deleted app-prod.yaml"
    fi
  fi
  echo "Waiting 15s for ArgoCD to clean up resources..."
  sleep 15
else
  echo "[SKIP] Cannot reach cluster, proceeding with terragrunt destroy"
fi

# 2. Destroy infrastructure with Terragrunt
echo ""
echo "--- Destroying Infrastructure ---"
TG_DIR="$PROJECT_ROOT/terragrunt/$ENVIRONMENT/eu-west-1"
if [ -d "$TG_DIR" ]; then
  cd "$TG_DIR"
  terragrunt run-all destroy -auto-approve --non-interactive
  echo "[OK] Infrastructure destroyed"
else
  echo "ERROR: Terragrunt directory not found: $TG_DIR"
  exit 1
fi

# 3. Force-delete Secrets Manager secret (avoids 30-day retention on re-deploy)
echo ""
echo "--- Cleaning up Secrets Manager ---"
SECRET_NAME="${CLUSTER_NAME}/app/config"
if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws secretsmanager delete-secret \
    --secret-id "$SECRET_NAME" \
    --force-delete-without-recovery \
    --region "$AWS_REGION" >/dev/null 2>&1 || true
  echo "[OK] Secret '$SECRET_NAME' force-deleted"
else
  echo "[OK] No secret to clean up"
fi

echo ""
echo "=== Teardown Complete ==="
echo ""
echo "Note: S3 state bucket, DynamoDB lock table, and ECR repo are preserved."
echo "To remove those too, run:"
echo "  aws s3 rb s3://${PROJECT}-terraform-state-\$(aws sts get-caller-identity --query Account --output text) --force"
echo "  aws dynamodb delete-table --table-name ${PROJECT}-terraform-locks --region $AWS_REGION"
echo "  aws ecr delete-repository --repository-name ${PROJECT}-nginx --region $AWS_REGION --force"
