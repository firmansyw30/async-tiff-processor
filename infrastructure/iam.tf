# ─────────────────────────────────────────────────────────────
# IAM — Spot Fleet Role
# ─────────────────────────────────────────────────────────────
resource "aws_iam_role" "spot_fleet_role" {
  name = "aws-ec2-spot-fleet-tagging-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = ""
        Effect    = "Allow"
        Principal = { Service = "spotfleet.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Owner   = var.owner_tag
    Project = var.project_tag
  }
}

# Grants: ec2 fleet ops, iam:PassRole (ec2 only), elb registration
resource "aws_iam_role_policy_attachment" "spot_fleet_tagging" {
  role       = aws_iam_role.spot_fleet_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2SpotFleetTaggingRole"
}

# ─────────────────────────────────────────────────────────────
# IAM — EC2 Worker Role
# ─────────────────────────────────────────────────────────────
resource "aws_iam_role" "worker_role" {
  name = "launch-template-ec2-s3-sqs-worker-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name    = "launch-template-ec2-s3-sqs-worker-role"
    Owner   = var.owner_tag
    Project = var.project_tag
  }
}

# Grants: CloudWatch metrics, logs, X-Ray tracing
resource "aws_iam_role_policy_attachment" "worker_cloudwatch" {
  role       = aws_iam_role.worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Grants: SSM session manager, patch management, inventory
resource "aws_iam_role_policy_attachment" "worker_ssm" {
  role       = aws_iam_role.worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Grants: sqs:* on all resources
resource "aws_iam_role_policy_attachment" "worker_sqs" {
  role       = aws_iam_role.worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
}

# Grants: s3:* and s3-object-lambda:* on all resources
resource "aws_iam_role_policy_attachment" "worker_s3" {
  role       = aws_iam_role.worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# Grants: ecr:GetAuthorizationToken, BatchGetImage,
#         GetDownloadUrlForLayer, BatchImportUpstreamImage
resource "aws_iam_role_policy_attachment" "worker_ecr" {
  role       = aws_iam_role.worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}

# Instance Profile — required to attach worker role to EC2
resource "aws_iam_instance_profile" "worker_profile" {
  name = "launch-template-ec2-s3-sqs-worker-role"
  role = aws_iam_role.worker_role.name
}