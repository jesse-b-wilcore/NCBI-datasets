locals {
  bucket_name = "cato-evidence-${var.environment}-${data.aws_caller_identity.current.account_id}"
  table_name  = "cato-evidence-${var.environment}"
}

data "aws_caller_identity" "current" {}

# ── S3 Evidence Bucket ────────────────────────────────────────────────────────

resource "aws_s3_bucket" "evidence" {
  bucket = local.bucket_name

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Purpose     = "cATO security evidence artifacts"
    GithubRepo  = "${var.github_org}/${var.github_repo}"
  }
}

resource "aws_s3_bucket_versioning" "evidence" {
  bucket = aws_s3_bucket.evidence.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "evidence" {
  bucket = aws_s3_bucket.evidence.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "evidence" {
  bucket = aws_s3_bucket.evidence.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "evidence" {
  bucket = aws_s3_bucket.evidence.id

  rule {
    id     = "transition-old-evidence"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 365
      storage_class = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 730
    }
  }
}

# ── DynamoDB Evidence Index ───────────────────────────────────────────────────

resource "aws_dynamodb_table" "evidence" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "commit_sha"
  range_key    = "evidence_type"

  attribute {
    name = "commit_sha"
    type = "S"
  }

  attribute {
    name = "evidence_type"
    type = "S"
  }

  attribute {
    name = "collected_at"
    type = "S"
  }

  global_secondary_index {
    name            = "collected_at-index"
    hash_key        = "evidence_type"
    range_key       = "collected_at"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Purpose     = "cATO evidence index"
  }
}
