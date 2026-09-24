resource "aws_ecr_repository" "python_make_transparent" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name    = var.ecr_repository_name
    Owner   = var.owner_tag
    Project = var.project_tag
  }

  lifecycle {
    prevent_destroy = true
  }
}