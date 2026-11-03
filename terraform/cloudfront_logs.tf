# --- CloudFront standard access logs ---
# Needed to break down the 4xx rate (bot scans vs real broken links). Legacy standard logging
# delivers via bucket ACL, so ACLs must be enabled on this bucket. Logs expire after 30 days.

resource "aws_s3_bucket" "cf_logs" {
  bucket = "asanchezbl-cloudfront-logs"

  tags = { Name = "${var.project_name}-cloudfront-logs" }
}

resource "aws_s3_bucket_public_access_block" "cf_logs" {
  bucket = aws_s3_bucket.cf_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "cf_logs" {
  bucket = aws_s3_bucket.cf_logs.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "cf_logs" {
  bucket     = aws_s3_bucket.cf_logs.id
  acl        = "private"
  depends_on = [aws_s3_bucket_ownership_controls.cf_logs]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cf_logs" {
  bucket = aws_s3_bucket.cf_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cf_logs" {
  bucket = aws_s3_bucket.cf_logs.id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }
  }
}
