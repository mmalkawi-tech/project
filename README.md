# AWS Disaster Recovery Solution
### TechConsulting — DevOps Project

Multi-region AWS infrastructure with automated failover, meeting **RTO: 30 minutes** and **RPO: 1 hour**.

---

## Architecture

| | Primary | DR |
|--|--|--|
| **Region** | us-east-1 | us-west-2 |
| **Compute** | ASG 2–6 EC2 | ASG 1→3 EC2 (warm) |
| **Database** | RDS MySQL Multi-AZ | Cross-region read replica |
| **Storage** | S3 + versioning | S3 CRR destination |
| **DNS** | Route53 PRIMARY | Route53 SECONDARY (auto-failover) |

See [docs/architecture.md](docs/architecture.md) for the full diagram.

---

## Project Structure

```
Project/
├── terraform/
│   ├── main.tf              # Root: Route53, CloudWatch, SNS, Backup
│   ├── providers.tf         # Dual-region AWS providers
│   ├── variables.tf
│   ├── outputs.tf
│   ├── example.tfvars       # Template — copy to terraform.tfvars
│   └── modules/
│       ├── networking/      # VPC, subnets, NAT, flow logs
│       ├── compute/         # ALB, Launch Template, ASG
│       ├── database/        # RDS MySQL (primary + replica)
│       └── storage/         # S3 with CRR and lifecycle
├── .github/workflows/
│   ├── terraform-plan.yml   # PR: plan + post diff as PR comment
│   ├── terraform-apply.yml  # Merge to main: auto-apply
│   └── dr-test.yml          # Weekly automated DR health check
├── scripts/
│   ├── health-check.sh      # Check environment readiness
│   └── failover.sh          # Manual failover procedure
└── docs/
    ├── architecture.md      # Architecture diagram and component list
    └── runbook.md           # Incident response and failback steps
```

---

## Quick Start

### Prerequisites
- Terraform >= 1.5
- AWS CLI configured
- S3 bucket `enhanceit-tfstate-dr` and DynamoDB table `terraform-state-lock` created for state backend

### Deploy

```bash
cd terraform
cp example.tfvars terraform.tfvars
# Edit terraform.tfvars with real credentials

terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

### Test DR Health

```bash
bash scripts/health-check.sh primary us-east-1
bash scripts/health-check.sh dr us-west-2
```

### Manual Failover

```bash
bash scripts/failover.sh --dry-run   # Preview
bash scripts/failover.sh             # Execute
```

---

## CI/CD Pipeline

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| `terraform-plan` | Pull Request | Lints, validates, runs plan, posts to PR |
| `terraform-apply` | Merge to `main` | Applies infrastructure (requires env approval) |
| `dr-test` | Every Sunday 02:00 UTC | Automated DR health and replication checks |

AWS credentials use **OIDC** — no long-lived access keys stored in GitHub.

---

## GitHub Secrets Required

| Secret | Description |
|--------|-------------|
| `DB_USERNAME` | RDS master username |
| `DB_PASSWORD` | RDS master password |

---

*Maintained by TechConsulting — moath.malkawi@techconsulting.tech*
