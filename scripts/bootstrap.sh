#!/usr/bin/env bash
# bootstrap.sh — One-time setup before GitHub Actions can run
# Run this locally with your AWS credentials configured.
# Creates:
#   1. S3 bucket for Terraform state
#   2. DynamoDB table for state locking
#   3. GitHub OIDC provider
#   4. IAM role for GitHub Actions
set -euo pipefail

ACCOUNT_ID="866934333672"
PRIMARY_REGION="us-east-1"
STATE_BUCKET="enhanceit-tfstate-dr"
LOCK_TABLE="terraform-state-lock"
OIDC_URL="token.actions.githubusercontent.com"
REPO="mmalkawi-tech/project"
ROLE_NAME="github-actions-dr-role"

log() { echo "[$(date +%H:%M:%S)] $*"; }

log "=== TechConsulting DR Bootstrap ==="

# --- 1. S3 state bucket ---
log "Step 1: Creating Terraform state S3 bucket..."
if aws s3api head-bucket --bucket "$STATE_BUCKET" --region "$PRIMARY_REGION" 2>/dev/null; then
  log "  Bucket already exists — skipping"
else
  aws s3api create-bucket \
    --bucket "$STATE_BUCKET" \
    --region "$PRIMARY_REGION"

  aws s3api put-bucket-versioning \
    --bucket "$STATE_BUCKET" \
    --versioning-configuration Status=Enabled

  aws s3api put-bucket-encryption \
    --bucket "$STATE_BUCKET" \
    --server-side-encryption-configuration '{
      "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
    }'

  aws s3api put-public-access-block \
    --bucket "$STATE_BUCKET" \
    --public-access-block-configuration \
      "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

  log "  Bucket created: $STATE_BUCKET"
fi

# --- 2. DynamoDB lock table ---
log "Step 2: Creating DynamoDB state lock table..."
if aws dynamodb describe-table --table-name "$LOCK_TABLE" --region "$PRIMARY_REGION" 2>/dev/null; then
  log "  Table already exists — skipping"
else
  aws dynamodb create-table \
    --table-name "$LOCK_TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$PRIMARY_REGION"

  aws dynamodb wait table-exists \
    --table-name "$LOCK_TABLE" \
    --region "$PRIMARY_REGION"

  log "  Table created: $LOCK_TABLE"
fi

# --- 3. GitHub OIDC provider ---
log "Step 3: Creating GitHub OIDC provider..."
OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_URL}"

if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" 2>/dev/null; then
  log "  OIDC provider already exists — skipping"
else
  aws iam create-open-id-connect-provider \
    --url "https://${OIDC_URL}" \
    --client-id-list "sts.amazonaws.com" \
    --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1"

  log "  OIDC provider created"
fi

# --- 4. IAM Role ---
log "Step 4: Creating GitHub Actions IAM role..."

TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_URL}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_URL}:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "${OIDC_URL}:sub": "repo:${REPO}:*"
        }
      }
    }
  ]
}
EOF
)

if aws iam get-role --role-name "$ROLE_NAME" 2>/dev/null; then
  log "  Role already exists — skipping"
else
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document "$TRUST_POLICY" \
    --description "Assumed by GitHub Actions in ${REPO} via OIDC"

  log "  Role created: $ROLE_NAME"
fi

# Attach AdministratorAccess for full Terraform access
# (scope this down after initial setup if desired)
aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"

log ""
log "=== Bootstrap complete ==="
log ""
log "Role ARN: arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
log ""
log "Next: re-run the failed GitHub Actions workflow from the GitHub UI."
