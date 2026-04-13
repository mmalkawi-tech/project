output "primary_alb_dns" {
  description = "Primary region ALB DNS name"
  value       = module.compute_primary.alb_dns_name
}

output "dr_alb_dns" {
  description = "DR region ALB DNS name"
  value       = module.compute_dr.alb_dns_name
}

output "primary_db_endpoint" {
  description = "Primary RDS endpoint"
  value       = module.database_primary.db_endpoint
  sensitive   = true
}

output "dr_db_endpoint" {
  description = "DR RDS replica endpoint"
  value       = module.database_dr.db_endpoint
  sensitive   = true
}

output "primary_s3_bucket" {
  description = "Primary S3 bucket name"
  value       = module.storage_primary.bucket_name
}

output "dr_s3_bucket" {
  description = "DR S3 replica bucket name"
  value       = module.storage_dr.bucket_name
}

output "route53_health_check_id" {
  description = "Route53 health check ID monitoring primary endpoint"
  value       = var.create_dns_records ? aws_route53_health_check.primary[0].id : null
}

output "sns_alert_topic_arn" {
  description = "SNS topic ARN for DR alerts"
  value       = aws_sns_topic.dr_alerts.arn
}
