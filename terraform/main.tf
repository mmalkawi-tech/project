# =============================================================================
# TechConsulting — AWS Disaster Recovery Infrastructure
# Primary Region: us-east-1  |  DR Region: us-west-2
# RTO: 30 minutes  |  RPO: 1 hour
# =============================================================================

# ---------- Networking: Primary ----------
module "networking_primary" {
  source = "./modules/networking"

  providers = { aws = aws.primary }

  project_name       = var.project_name
  vpc_cidr           = var.primary_vpc_cidr
  region             = var.primary_region
  availability_zones = ["${var.primary_region}a", "${var.primary_region}b", "${var.primary_region}c"]
  environment        = var.environment
}

# ---------- Networking: DR ----------
module "networking_dr" {
  source = "./modules/networking"

  providers = { aws = aws.dr }

  project_name       = var.project_name
  vpc_cidr           = var.dr_vpc_cidr
  region             = var.dr_region
  availability_zones = ["${var.dr_region}a", "${var.dr_region}b"]
  environment        = "${var.environment}-dr"
}

# ---------- Compute: Primary ----------
module "compute_primary" {
  source = "./modules/compute"

  providers = { aws = aws.primary }

  project_name         = var.project_name
  environment          = var.environment
  vpc_id               = module.networking_primary.vpc_id
  public_subnet_ids    = module.networking_primary.public_subnet_ids
  private_subnet_ids   = module.networking_primary.private_subnet_ids
  instance_type        = var.app_instance_type
  asg_min_size         = var.asg_min_size
  asg_max_size         = var.asg_max_size
  asg_desired_capacity = var.asg_desired_capacity
  db_endpoint          = module.database_primary.db_endpoint
}

# ---------- Compute: DR (warm standby) ----------
module "compute_dr" {
  source = "./modules/compute"

  providers = { aws = aws.dr }

  project_name         = var.project_name
  environment          = "${var.environment}-dr"
  vpc_id               = module.networking_dr.vpc_id
  public_subnet_ids    = module.networking_dr.public_subnet_ids
  private_subnet_ids   = module.networking_dr.private_subnet_ids
  instance_type        = var.app_instance_type
  asg_min_size         = var.dr_asg_min_size
  asg_max_size         = var.asg_max_size
  asg_desired_capacity = var.dr_asg_min_size
  db_endpoint          = module.database_dr.db_endpoint
}

# ---------- Database: Primary ----------
module "database_primary" {
  source = "./modules/database"

  providers = { aws = aws.primary }

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.networking_primary.vpc_id
  private_subnet_ids = module.networking_primary.private_subnet_ids
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = var.db_password
  instance_class     = var.db_instance_class
  is_primary         = true
  source_db_arn      = null
}

# ---------- Database: DR (cross-region read replica) ----------
module "database_dr" {
  source = "./modules/database"

  providers = { aws = aws.dr }

  project_name       = var.project_name
  environment        = "${var.environment}-dr"
  vpc_id             = module.networking_dr.vpc_id
  private_subnet_ids = module.networking_dr.private_subnet_ids
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = var.db_password
  instance_class     = var.db_instance_class
  is_primary         = false
  source_db_arn      = module.database_primary.db_arn
}

# ---------- Storage: Primary S3 ----------
module "storage_primary" {
  source = "./modules/storage"

  providers = { aws = aws.primary }

  project_name        = var.project_name
  environment         = var.environment
  region              = var.primary_region
  replication_role_arn = aws_iam_role.s3_replication.arn
  destination_bucket_arn = module.storage_dr.bucket_arn
}

# ---------- Storage: DR S3 (replica) ----------
module "storage_dr" {
  source = "./modules/storage"

  providers = { aws = aws.dr }

  project_name           = var.project_name
  environment            = "${var.environment}-dr"
  region                 = var.dr_region
  replication_role_arn   = null
  destination_bucket_arn = null
}

# ---------- S3 Replication IAM Role ----------
resource "aws_iam_role" "s3_replication" {
  provider = aws.primary
  name     = "${var.project_name}-s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "s3_replication" {
  provider = aws.primary
  name     = "${var.project_name}-s3-replication-policy"
  role     = aws_iam_role.s3_replication.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
        Resource = [module.storage_primary.bucket_arn]
      },
      {
        Effect = "Allow"
        Action = ["s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl", "s3:GetObjectVersionTagging"]
        Resource = ["${module.storage_primary.bucket_arn}/*"]
      },
      {
        Effect = "Allow"
        Action = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"]
        Resource = ["${module.storage_dr.bucket_arn}/*"]
      }
    ]
  })
}

# ---------- AWS Backup: Automated Backups ----------
resource "aws_backup_vault" "primary" {
  provider = aws.primary
  name     = "${var.project_name}-backup-vault"
}

resource "aws_backup_plan" "dr_backup" {
  provider = aws.primary
  name     = "${var.project_name}-dr-backup-plan"

  rule {
    rule_name         = "hourly-backup"
    target_vault_name = aws_backup_vault.primary.name
    schedule          = "cron(0 * * * ? *)" # Every hour — meets 1h RPO

    lifecycle {
      delete_after = 30
    }

    copy_action {
      destination_vault_arn = aws_backup_vault.dr.arn
    }
  }
}

resource "aws_backup_vault" "dr" {
  provider = aws.dr
  name     = "${var.project_name}-backup-vault-dr"
}

resource "aws_backup_selection" "rds_backup" {
  provider     = aws.primary
  iam_role_arn = aws_iam_role.backup.arn
  name         = "${var.project_name}-rds-backup"
  plan_id      = aws_backup_plan.dr_backup.id

  resources = [module.database_primary.db_arn]
}

resource "aws_iam_role" "backup" {
  provider = aws.primary
  name     = "${var.project_name}-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "backup" {
  provider   = aws.primary
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

# ---------- Route53 Health Check & DNS Failover ----------
resource "aws_route53_health_check" "primary" {
  provider          = aws.primary
  fqdn              = module.compute_primary.alb_dns_name
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30

  tags = { Name = "${var.project_name}-primary-health-check" }
}

resource "aws_route53_record" "primary" {
  provider = aws.primary
  zone_id  = data.aws_route53_zone.main.zone_id
  name     = "app.techconsulting.tech"
  type     = "A"

  set_identifier = "primary"

  failover_routing_policy {
    type = "PRIMARY"
  }

  health_check_id = aws_route53_health_check.primary.id

  alias {
    name                   = module.compute_primary.alb_dns_name
    zone_id                = module.compute_primary.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "dr" {
  provider = aws.primary
  zone_id  = data.aws_route53_zone.main.zone_id
  name     = "app.techconsulting.tech"
  type     = "A"

  set_identifier = "dr-failover"

  failover_routing_policy {
    type = "SECONDARY"
  }

  alias {
    name                   = module.compute_dr.alb_dns_name
    zone_id                = module.compute_dr.alb_zone_id
    evaluate_target_health = true
  }
}

data "aws_route53_zone" "main" {
  provider = aws.primary
  name     = "techconsulting.tech"
}

# ---------- SNS: DR Alerts ----------
resource "aws_sns_topic" "dr_alerts" {
  provider = aws.primary
  name     = "${var.project_name}-dr-alerts"
}

resource "aws_sns_topic_subscription" "email_alert" {
  provider  = aws.primary
  topic_arn = aws_sns_topic.dr_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ---------- CloudWatch: Alarms ----------
resource "aws_cloudwatch_metric_alarm" "primary_alb_unhealthy" {
  provider            = aws.primary
  alarm_name          = "${var.project_name}-alb-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "Primary ALB has unhealthy targets — DR failover may be triggered"
  alarm_actions       = [aws_sns_topic.dr_alerts.arn]

  dimensions = {
    LoadBalancer = module.compute_primary.alb_arn_suffix
    TargetGroup  = module.compute_primary.target_group_arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "primary_db_cpu" {
  provider            = aws.primary
  alarm_name          = "${var.project_name}-rds-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 90
  alarm_description   = "Primary RDS CPU above 90% — check for failover conditions"
  alarm_actions       = [aws_sns_topic.dr_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = module.database_primary.db_id
  }
}

resource "aws_cloudwatch_metric_alarm" "primary_db_connections" {
  provider            = aws.primary
  alarm_name          = "${var.project_name}-rds-connection-failure"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Primary RDS has no connections — potential outage"
  alarm_actions       = [aws_sns_topic.dr_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = module.database_primary.db_id
  }
}
