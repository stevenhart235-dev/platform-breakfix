locals {
  ecr_destroyable_repositories = {
    for key, repository in var.ecr_repositories : key => repository
    if !repository.preserve_on_destroy
  }
  ecr_preserved_repositories = {
    for key, repository in var.ecr_repositories : key => repository
    if repository.preserve_on_destroy
  }
}

resource "aws_ecr_repository" "destroyable" {
  for_each = local.ecr_destroyable_repositories

  name                 = each.value.name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  encryption_configuration {
    encryption_type = "AES256"
  }
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "preserved" {
  for_each = local.ecr_preserved_repositories

  name                 = each.value.name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  encryption_configuration {
    encryption_type = "AES256"
  }
  image_scanning_configuration {
    scan_on_push = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ecr_lifecycle_policy" "destroyable" {
  for_each = aws_ecr_repository.destroyable

  repository = each.value.name
  policy     = local.ecr_lifecycle_policies[each.key]
}

resource "aws_ecr_lifecycle_policy" "preserved" {
  for_each = aws_ecr_repository.preserved

  repository = each.value.name
  policy     = local.ecr_lifecycle_policies[each.key]

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  ecr_lifecycle_policies = {
    for key, repository in var.ecr_repositories : key => jsonencode({
      rules = [
        {
          rulePriority = 1
          description  = "Expire untagged images after ${repository.max_untagged_image_age} days"
          selection = {
            tagStatus   = "untagged"
            countType   = "sinceImagePushed"
            countUnit   = "days"
            countNumber = repository.max_untagged_image_age
          }
          action = { type = "expire" }
        },
        {
          rulePriority = 2
          description  = "Retain the ${repository.max_tagged_images} most recent tagged images"
          selection = {
            tagStatus      = "tagged"
            tagPatternList = ["*"]
            countType      = "imageCountMoreThan"
            countNumber    = repository.max_tagged_images
          }
          action = { type = "expire" }
        },
      ]
    })
  }
}
