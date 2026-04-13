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

resource "aws_db_instance" "main" {
  identifier        = "${var.project_name}-db-${var.environment}"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = var.instance_class
  db_name           = var.is_primary ? var.db_name : null
  username          = var.is_primary ? var.db_username : null
  password          = var.is_primary ? var.db_password : null
  replicate_source_db = var.is_primary ? null : var.source_db_arn

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]

  allocated_storage     = 100
  max_allocated_storage = 500
  storage_type          = "gp3"
  storage_encrypted     = true

  backup_retention_period = var.is_primary ? 7 : 0
  backup_window           = "02:00-03:00"
  maintenance_window      = "Sun:04:00-Sun:05:00"

  multi_az               = var.is_primary
  deletion_protection    = true
  skip_final_snapshot    = false
  final_snapshot_identifier = "${var.project_name}-db-final-${var.environment}"

  performance_insights_enabled = true
  monitoring_interval          = 60

  tags = { Name = "${var.project_name}-db-${var.environment}" }
}
