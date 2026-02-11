#!/bin/bash
set -euo pipefail

AWS_REGION="eu-west-1"
ACCOUNT_ID="530424100135"
PROJECT="project-circle"
BUCKET="${PROJECT}-terraform-state-${ACCOUNT_ID}"
TABLE="${PROJECT}-terraform-locks"

echo "=== Project Circle - Setup ==="

# Check prerequisites
for cmd in aws terraform terragrunt kubectl helm; do
  command -v $cmd >/dev/null 2>&1 || { echo "ERROR: $cmd not found"; exit 1; }
done
echo "[OK] Prerequisites verified"

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
echo "Next: cd terragrunt/dev/eu-west-1 && terragrunt run-all apply"
