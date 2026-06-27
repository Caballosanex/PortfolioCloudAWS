# ECR repositories for backend images
locals {
  ecr_repos = [
    "serp-backend",
    "catlink-backend",
    "matchcota-backend",
    "matchcota-db",
  ]
}

resource "aws_ecr_repository" "backends" {
  for_each = toset(local.ecr_repos)

  name                 = "${var.project_name}/${each.key}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = {
    Name = "${var.project_name}-${each.key}"
  }
}

resource "aws_ecr_lifecycle_policy" "backends" {
  for_each   = aws_ecr_repository.backends
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = {
        type = "expire"
      }
    }]
  })
}
