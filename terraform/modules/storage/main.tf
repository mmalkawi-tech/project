resource "aws_s3_bucket" "main" {
  bucket        = "${var.project_name}-data-${var.environment}-${var.region}"
  force_destroy = false
}

resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "main" {
  bucket                  = aws_s3_bucket.main.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"
    filter { prefix = "" }
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
    expiration { days = 365 }
  }
}

resource "aws_s3_bucket_replication_configuration" "main" {
  count = var.replication_role_arn != null ? 1 : 0

  bucket = aws_s3_bucket.main.id
  role   = var.replication_role_arn

  rule {
    id     = "replicate-all"
    status = "Enabled"
    filter { prefix = "" }
    destination {
      bucket        = var.destination_bucket_arn
      storage_class = "STANDARD_IA"
    }
    delete_marker_replication { status = "Enabled" }
  }

  depends_on = [aws_s3_bucket_versioning.main]
}
