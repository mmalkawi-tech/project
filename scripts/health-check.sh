#!/usr/bin/env bash
# health-check.sh — Verify DR environment readiness
# Usage: ./health-check.sh <environment> <aws-region>
set -euo pipefail

ENV="${1:-primary}"
REGION="${2:-us-east-1}"
PROJECT="tc-dr"
FAILURES=0

echo "=========================================="
echo "  DR Health Check: ${ENV} (${REGION})"
echo "  $(date -u)"
echo "=========================================="

check() {
  local name="$1"
  local cmd="$2"
  echo -n "  Checking ${name}... "
  if eval "$cmd" > /dev/null 2>&1; then
    echo "OK"
  else
    echo "FAIL"
    FAILURES=$((FAILURES + 1))
  fi
}

# --- EC2 / ASG ---
check "ASG exists" \
  "aws autoscaling describe-auto-scaling-groups \
     --auto-scaling-group-names ${PROJECT}-asg-${ENV} \
     --region ${REGION} \
     --query 'AutoScalingGroups[0].AutoScalingGroupName'"

# --- ALB ---
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names "${PROJECT}-alb-${ENV}" \
  --region "${REGION}" \
  --query 'LoadBalancers[0].DNSName' \
  --output text 2>/dev/null || echo "")

if [[ -n "${ALB_DNS}" && "${ALB_DNS}" != "None" ]]; then
  check "ALB reachable" "curl -sf --max-time 10 http://${ALB_DNS}/health"
else
  echo "  Checking ALB reachable... SKIP (ALB not found)"
  FAILURES=$((FAILURES + 1))
fi

# --- RDS ---
check "RDS available" \
  "aws rds describe-db-instances \
     --db-instance-identifier ${PROJECT}-db-${ENV} \
     --region ${REGION} \
     --query 'DBInstances[0].DBInstanceStatus' | grep -q available"

# --- S3 ---
check "S3 bucket accessible" \
  "aws s3 ls s3://${PROJECT}-data-${ENV}-${REGION} --region ${REGION}"

echo "=========================================="
if [[ ${FAILURES} -eq 0 ]]; then
  echo "  RESULT: ALL CHECKS PASSED"
  exit 0
else
  echo "  RESULT: ${FAILURES} CHECK(S) FAILED"
  exit 1
fi
