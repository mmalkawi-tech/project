resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project_name}-rds-monitoring-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg-${var.environment}"
  description = "Allow MySQL from app layer"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group-${var.environment}"
  subnet_ids = var.private_subnet_ids
}

# KMS key for encrypting the replica in the DR region
resource "aws_kms_key" "rds" {
  count               = var.is_primary ? 0 : 1
  description         = "${var.project_name} RDS encryption key (${var.environment})"
  enable_key_rotation = true
}

resource "aws_db_instance" "main" {
  identifier          = "${var.project_name}-db-${var.environment}"
  engine              = var.is_primary ? "mysql" : null
  engine_version      = var.is_primary ? "8.0" : null
  instance_class      = var.instance_class
  db_name             = var.is_primary ? var.db_name : null
  username            = var.is_primary ? var.db_username : null
  password            = var.is_primary ? var.db_password : null
  replicate_source_db = var.is_primary ? null : var.source_db_arn

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]

  # allocated_storage is ignored for replicas (inherited from primary)
  allocated_storage     = var.is_primary ? 100 : null
  max_allocated_storage = var.is_primary ? 500 : null
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.is_primary ? null : aws_kms_key.rds[0].arn

  backup_retention_period   = var.is_primary ? 7 : 0
  backup_window             = "02:00-03:00"
  maintenance_window        = "Sun:04:00-Sun:05:00"

  multi_az               = var.is_primary
  deletion_protection    = true
  skip_final_snapshot    = false
  final_snapshot_identifier = "${var.project_name}-db-final-${var.environment}"

  performance_insights_enabled = true
  monitoring_interval          = 60
  monitoring_role_arn          = aws_iam_role.rds_monitoring.arn

  tags = { Name = "${var.project_name}-db-${var.environment}" }
}
