#!/usr/bin/env bash
# failover.sh — Manual DR failover script
# Usage: ./failover.sh [--dry-run]
#
# Steps:
#  1. Promote RDS read replica to standalone
#  2. Scale DR ASG to full capacity
#  3. Update Route53 to force traffic to DR (optional — Route53 health checks
#     handle this automatically; use only if manual override is needed)
#
set -euo pipefail

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

PRIMARY_REGION="us-east-1"
DR_REGION="us-west-2"
PROJECT="tc-dr"
DR_DB="${PROJECT}-db-prod-dr"
DR_ASG="${PROJECT}-asg-prod-dr"
DR_DESIRED=3

log()  { echo "[$(date -u +%H:%M:%S)] $*"; }
run()  { if $DRY_RUN; then echo "[DRY-RUN] $*"; else eval "$@"; fi; }

log "=========================================="
log "  TechConsulting — DR FAILOVER INITIATED"
log "  Mode: $( $DRY_RUN && echo DRY-RUN || echo LIVE )"
log "=========================================="

# --- Step 1: Verify primary is actually down ---
log "Step 1: Checking primary region health..."
PRIMARY_ALB=$(aws elbv2 describe-load-balancers \
  --names "${PROJECT}-alb-prod" \
  --region "${PRIMARY_REGION}" \
  --query 'LoadBalancers[0].DNSName' \
  --output text 2>/dev/null || echo "")

if [[ -z "${PRIMARY_ALB}" || "${PRIMARY_ALB}" == "None" ]]; then
  log "Primary ALB not found — proceeding with failover"
else
  HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" --max-time 10 "http://${PRIMARY_ALB}/health" || echo "000")
  if [[ "${HTTP_CODE}" == "200" ]]; then
    log "WARNING: Primary appears healthy (HTTP ${HTTP_CODE}). Failover may not be needed."
    if ! $DRY_RUN; then
      read -rp "Continue anyway? [y/N] " confirm
      [[ "${confirm}" =~ ^[Yy]$ ]] || { log "Failover aborted."; exit 0; }
    fi
  fi
fi

# --- Step 2: Promote DR RDS replica ---
log "Step 2: Promoting RDS read replica in ${DR_REGION}..."
run aws rds promote-read-replica \
  --db-instance-identifier "${DR_DB}" \
  --region "${DR_REGION}"

log "Waiting for RDS promotion to complete..."
if ! $DRY_RUN; then
  aws rds wait db-instance-available \
    --db-instance-identifier "${DR_DB}" \
    --region "${DR_REGION}"
fi
log "RDS promotion complete."

# --- Step 3: Scale DR ASG to full capacity ---
log "Step 3: Scaling DR ASG to ${DR_DESIRED} instances..."
run aws autoscaling set-desired-capacity \
  --auto-scaling-group-name "${DR_ASG}" \
  --desired-capacity "${DR_DESIRED}" \
  --region "${DR_REGION}"

log "Waiting for ASG instances to be healthy..."
if ! $DRY_RUN; then
  sleep 60
fi

# --- Step 4: Update Route53 weight (force DR) ---
log "Step 4: Route53 failover is automatic via health checks."
log "        If health check has not triggered, you can disable the primary"
log "        record manually in the AWS Console or via Route53 API."

# --- Done ---
log "=========================================="
log "  FAILOVER COMPLETE"
log "  Traffic should now route to: ${DR_REGION}"
log "  Verify at: https://app.techconsulting.tech"
log "=========================================="
