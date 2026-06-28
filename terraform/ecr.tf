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
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last 2 tagged images"
        selection = {
          tagStatus   = "tagged"
          tagPrefixList = ["latest"]
          countType   = "imageCountMoreThan"
          countNumber = 2
        }
        action = { type = "expire" }
      }
    ]
  })
}
