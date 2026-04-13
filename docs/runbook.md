# DR Runbook — TechConsulting

## Incident Response: Triggering Failover

### Automatic Failover (preferred)
Route53 health checks detect primary failure automatically.
- Detection: ~90 seconds (3 × 30s intervals)
- DNS TTL: 60 seconds
- **No action required** — traffic routes to DR automatically

### Manual Failover (override)

```bash
# Dry run first
bash scripts/failover.sh --dry-run

# Live failover
bash scripts/failover.sh
```

Steps the script performs:
1. Checks if primary is actually down
2. Promotes DR RDS read replica to standalone primary
3. Scales DR ASG from 1 → 3 instances
4. Route53 failover is handled automatically by health checks

### After Failover — What to Check
- [ ] Route53 has switched to DR record
- [ ] DR ALB health check is green (all targets healthy)
- [ ] RDS promotion completed (`aws rds describe-db-instances ...`)
- [ ] Application logs show traffic in `us-west-2`
- [ ] Alert team via Slack / email

---

## Failback to Primary (after primary is restored)

1. Fix the root cause in `us-east-1`
2. Re-establish RDS replication (create new read replica pointing at DR)
3. Wait for replica lag < 1 minute
4. Scale primary ASG back to desired capacity
5. Route53 health check automatically restores primary record once `/health` returns 200
6. Scale DR ASG back to 1 (warm standby)

---

## Weekly DR Test (automated)

The `dr-test.yml` workflow runs every Sunday at 02:00 UTC.

Checks performed:
- Primary and DR ASGs exist and have healthy instances
- Both ALBs respond to `/health`
- RDS read replica lag < 1h
- S3 replication is active

Failures are reported as GitHub Actions failures and trigger SNS alerts.

---

## Key AWS Resources

| Resource | Name | Region |
|----------|------|--------|
| Primary VPC | tc-dr-vpc-prod | us-east-1 |
| DR VPC | tc-dr-vpc-prod-dr | us-west-2 |
| Primary RDS | tc-dr-db-prod | us-east-1 |
| DR RDS Replica | tc-dr-db-prod-dr | us-west-2 |
| Primary S3 | tc-dr-data-prod-us-east-1 | us-east-1 |
| DR S3 | tc-dr-data-prod-dr-us-west-2 | us-west-2 |
| SNS Alert Topic | tc-dr-dr-alerts | us-east-1 |
| Route53 Health Check | primary | global |

---

## Terraform State

- **S3 Bucket:** `enhanceit-tfstate-dr`
- **DynamoDB Table:** `terraform-state-lock`
- **Region:** us-east-1
