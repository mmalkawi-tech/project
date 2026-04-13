# Disaster Recovery Architecture

## Overview

**Organization:** TechConsulting
**Strategy:** Warm Standby (Active/Passive)
**RTO:** 30 minutes
**RPO:** 1 hour

## Regions

| Role    | Region    | Description                  |
|---------|-----------|------------------------------|
| Primary | us-east-1 | Handles all production traffic |
| DR      | us-west-2 | Warm standby — scales on failover |

## Architecture Diagram

```
Internet
    │
    ▼
Route53 (Failover Routing + Health Check)
    │
    ├──── Primary Record (ACTIVE) ──────────────────────────────┐
    │                                                           │
    │         us-east-1 (PRIMARY)                               │
    │   ┌─────────────────────────────────────┐                 │
    │   │  ALB  →  ASG (2–6 EC2 instances)   │                 │
    │   │            │                         │                 │
    │   │          RDS MySQL (Multi-AZ)        │                 │
    │   │            │  (cross-region repl.)   │                 │
    │   │          S3 (versioned + CRR) ──────►│── us-west-2 S3 │
    │   │          AWS Backup (hourly)         │                 │
    │   └─────────────────────────────────────┘                 │
    │                                                           │
    └──── Secondary Record (STANDBY) ──────────────────────────┘
                  │
              us-west-2 (DR)
        ┌─────────────────────────────────────┐
        │  ALB  →  ASG (1 warm EC2 → scales)  │
        │            │                         │
        │          RDS Read Replica             │
        │            (promoted on failover)     │
        │          S3 (CRR destination)         │
        └─────────────────────────────────────┘
```

## Components

### Networking
- VPC with public/private subnets across 3 AZs (primary) / 2 AZs (DR)
- NAT Gateways per AZ for high availability
- VPC Flow Logs to CloudWatch

### Compute
- Application Load Balancer with HTTPS redirect
- Auto Scaling Group with health checks tied to ALB
- Amazon Linux 2023 EC2 instances (launch template)
- ASG scales 2→6 in primary; starts at 1 in DR (scales to 3 on failover)

### Database
- Amazon RDS MySQL 8.0
- Primary: Multi-AZ enabled, 7-day backup retention
- DR: Cross-region read replica, promoted to standalone during failover

### Storage
- S3 with versioning, KMS encryption, public access block
- Cross-Region Replication (CRR) from primary to DR bucket
- Lifecycle: STANDARD → STANDARD_IA (30d) → GLACIER (90d) → Expire (365d)

### Backups
- AWS Backup plan: hourly backups copied cross-region
- Meets the 1h RPO requirement

### DNS & Failover
- Route53 health check monitors primary ALB `/health` every 30s
- 3 consecutive failures trigger automatic failover to DR record
- Failover triggers within ~90 seconds of primary going down

### Monitoring & Alerts
- CloudWatch alarms: ALB unhealthy hosts, RDS high CPU, RDS connection drop
- SNS topic → email alerts to moath.malkawi@techconsulting.tech

## CI/CD Pipeline

| Workflow | Trigger | Action |
|----------|---------|--------|
| `terraform-plan.yml` | Pull Request to `main` | Runs plan and posts diff to PR |
| `terraform-apply.yml` | Merge to `main` | Applies infrastructure changes |
| `dr-test.yml` | Every Sunday 02:00 UTC | Automated DR health check |

All pipelines use OIDC (no long-lived AWS keys) and require `environment: production` approval gate on apply.
