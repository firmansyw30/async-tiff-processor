# ─────────────────────────────────────────────────────────────
# Data Source — VPC (pre-existing)
# ─────────────────────────────────────────────────────────────
data "aws_vpc" "main" {
  id = var.vpc_id
}

# ─────────────────────────────────────────────────────────────
# Security Group — standart (worker instance)
# ─────────────────────────────────────────────────────────────
resource "aws_security_group" "worker_sg" {
  name        = "standart"
  description = "Allows ssh only"
  vpc_id      = data.aws_vpc.main.id

  tags = {
    Name = "standart"
  }
}

# ── Inbound: SSH ──────────────────────────────────────────────
resource "aws_vpc_security_group_ingress_rule" "worker_ssh" {
  security_group_id = aws_security_group.worker_sg.id
  description       = "Allow SSH from anywhere"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = "0.0.0.0/0"
}

# ── Outbound: All traffic ─────────────────────────────────────
resource "aws_vpc_security_group_egress_rule" "worker_egress_all" {
  security_group_id = aws_security_group.worker_sg.id
  description       = "Allow all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ─────────────────────────────────────────────────────────────
# Launch Template — sqs-worker
# ─────────────────────────────────────────────────────────────
resource "aws_launch_template" "sqs_worker" {
  name     = "sqs-worker"
  image_id = var.worker_ami
  key_name = var.key_name

  # instance_type intentionally omitted — overridden per Spot Fleet override

  iam_instance_profile {
    arn = aws_iam_instance_profile.worker_profile.arn
  }

  network_interfaces {
    associate_public_ip_address = true
    device_index                = 0
    security_groups             = [aws_security_group.worker_sg.id]
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 10
      volume_type           = "gp3"
      iops                  = 3000
      throughput            = 125
      encrypted             = false
      delete_on_termination = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    source_bucket       = aws_s3_bucket.worker_source_code.bucket
    aws_region          = var.region
    sqs_queue_url       = aws_sqs_queue.tiff_queue_upload_file_queue.id
    worker_docker_image = "${aws_ecr_repository.python_make_transparent.repository_url}:${var.ecr_image_tag}"
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "sqs-worker"
      Owner   = var.owner_tag
      Project = var.project_tag
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_iam_instance_profile.worker_profile]
}