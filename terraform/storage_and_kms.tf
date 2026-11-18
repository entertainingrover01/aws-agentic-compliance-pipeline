resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_kms_key" "pipeline" {
  description             = "KMS CMK for Agentic Compliance Pipeline S3 and SQS encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

locals {
  buckets = toset(["raw", "curated", "audit", "athena-results"])
}

resource "aws_s3_bucket" "buckets" {
  for_each      = local.buckets
  bucket        = "agentic-compliance-${each.key}-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "buckets" {
  for_each                = aws_s3_bucket.buckets
  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "buckets" {
  for_each = aws_s3_bucket.buckets
  bucket   = each.value.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.pipeline.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_notification" "raw_eventbridge" {
  bucket      = aws_s3_bucket.buckets["raw"].id
  eventbridge = true
}
