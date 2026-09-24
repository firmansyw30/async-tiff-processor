# ─────────────────────────────────────────────────────────────
# S3 — tiff-bucket (public upload bucket)
# ─────────────────────────────────────────────────────────────
resource "aws_s3_bucket" "tiff_bucket" {
  bucket = var.mapid_bucket_name

  tags = {
    Name    = "tiff-bucket"
    Owner   = "${var.owner_tag}"
    Project = var.project_tag
  }
}

resource "aws_s3_bucket_public_access_block" "tiff_bucket" {
  bucket = aws_s3_bucket.tiff_bucket.id

  block_public_acls       = false
  ignore_public_acls      = false
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "tiff_bucket" {
  bucket = aws_s3_bucket.tiff_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.tiff_bucket.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.tiff_bucket]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tiff_bucket" {
  bucket = aws_s3_bucket.tiff_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "tiff_bucket" {
  bucket = aws_s3_bucket.tiff_bucket.id

  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_bucket_cors_configuration" "tiff_bucket" {
  bucket = aws_s3_bucket.tiff_bucket.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["HEAD", "GET", "PUT", "POST", "DELETE"]
    allowed_origins = ["*"]
    expose_headers = [
      "x-amz-server-side-encryption",
      "x-amz-request-id",
      "x-amz-id-2",
      "ETag",
    ]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_notification" "tiff_bucket" {
  bucket = aws_s3_bucket.tiff_bucket.id

  queue {
    id        = "tiff-queue-upload"
    queue_arn = aws_sqs_queue.tiff_queue_upload_file_queue.arn
    events    = ["s3:ObjectCreated:*"]

    filter_prefix = "tiff/"
  }
}

# ─────────────────────────────────────────────────────────────
# S3 — worker-source-code (private, internal use)
# ─────────────────────────────────────────────────────────────
resource "aws_s3_bucket" "worker_source_code" {
  bucket = var.source_bucket_name

  tags = {
    Name    = "worker-source-code"
    Owner   = var.owner_tag
    Project = var.project_tag
  }
}

resource "aws_s3_bucket_public_access_block" "worker_source_code" {
  bucket = aws_s3_bucket.worker_source_code.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "worker_source_code" {
  bucket = aws_s3_bucket.worker_source_code.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "worker_source_code" {
  bucket = aws_s3_bucket.worker_source_code.id

  versioning_configuration {
    status = "Disabled"
  }
}