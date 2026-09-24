resource "aws_sqs_queue" "tiff_queue_upload_file_queue" {
  name                       = var.queue_name
  visibility_timeout_seconds = var.queue_visibility_timeout
  message_retention_seconds  = 345600  # 4 days
  max_message_size           = 1048576 # 1 MB
  delay_seconds              = 0
  receive_wait_time_seconds  = 0

  tags = {
    Name    = var.queue_name
    Owner   = var.owner_tag
    Project = var.project_tag
  }
}

resource "aws_sqs_queue_policy" "tiff_queue_upload_file_queue" {
  queue_url = aws_sqs_queue.tiff_queue_upload_file_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "__default_policy_ID"
    Statement = [

      # Full access for account root
      {
        Sid    = "__owner_statement"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "SQS:*"
        Resource = aws_sqs_queue.tiff_queue_upload_file_queue.arn
      },

      # Worker role — send + consume messages
      {
        Sid    = "__worker_statement"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.worker_role.arn
        }
        Action = [
          "SQS:SendMessage",
          "SQS:ReceiveMessage",
          "SQS:DeleteMessage",
          "SQS:ChangeMessageVisibility",
        ]
        Resource = aws_sqs_queue.tiff_queue_upload_file_queue.arn
      },

      # S3 tiff-bucket — event notification
      {
        Sid    = "AllowS3EventNotification"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "SQS:SendMessage"
        Resource = aws_sqs_queue.tiff_queue_upload_file_queue.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.tiff_bucket.arn
          }
        }
      },
    ]
  })
}