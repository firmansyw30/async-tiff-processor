output "mapid_bucket" {
  description = "Public bucket receiving TIFF uploads"
  value       = aws_s3_bucket.tiff_bucket.bucket
}

output "source_code_bucket" {
  description = "Private bucket holding the worker source code"
  value       = aws_s3_bucket.worker_source_code.bucket
}

output "queue_url" {
  description = "SQS queue URL for the worker"
  value       = aws_sqs_queue.hki_upload_file_queue.id
}

output "queue_arn" {
  description = "SQS queue ARN"
  value       = aws_sqs_queue.hki_upload_file_queue.arn
}

output "ecr_repository_url" {
  description = "ECR repository URL for the make_transparent image"
  value       = aws_ecr_repository.python_make_transparent.repository_url
}

output "worker_docker_image" {
  description = "Full image reference pulled by the worker"
  value       = "${aws_ecr_repository.python_make_transparent.repository_url}:${var.ecr_image_tag}"
}

output "launch_template_id" {
  description = "Launch template ID"
  value       = aws_launch_template.hki_sqs_worker.id
}

output "launch_template_latest_version" {
  description = "Latest launch template version used by the fleet"
  value       = aws_launch_template.hki_sqs_worker.latest_version
}

output "spot_fleet_request_id" {
  description = "Spot Fleet request ID"
  value       = aws_spot_fleet_request.sqs_worker_fleet.id
}

output "worker_role_arn" {
  description = "EC2 worker IAM role ARN"
  value       = aws_iam_role.worker_role.arn
}

output "worker_instance_profile_name" {
  description = "EC2 instance profile name"
  value       = aws_iam_instance_profile.worker_profile.name
}

output "spot_fleet_role_arn" {
  description = "Spot Fleet IAM role ARN"
  value       = aws_iam_role.spot_fleet_role.arn
}