variable "aws_region" {
  description = "AWS region in which to query and eventually create lab infrastructure."
  type        = string
  default     = "us-east-2"
}

variable "cluster_name" {
  description = "Name to use for the future EKS cluster and related resources."
  type        = string
  default     = "platform-breakfix"
}

variable "kubernetes_version" {
  description = "Kubernetes minor version for the EKS control plane and managed addons."
  type        = string
  default     = "1.36"
}

variable "eks_lifetime_hours" {
  description = "Creation-only advisory lifetime for a new EKS lab lifecycle."
  type        = number
  default     = 4

  validation {
    condition     = var.eks_lifetime_hours >= 1 && var.eks_lifetime_hours <= 24 && floor(var.eks_lifetime_hours) == var.eks_lifetime_hours
    error_message = "EKS lifetime must be a whole number of hours from 1 through 24."
  }
}

variable "ecr_repositories" {
  description = "ECR repositories to create, keyed by a stable logical identifier."
  type = map(object({
    name                   = string
    preserve_on_destroy    = optional(bool, false)
    max_untagged_image_age = optional(number, 7)
    max_tagged_images      = optional(number, 20)
  }))
  default = {}

  validation {
    condition = alltrue([
      for repository in values(var.ecr_repositories) :
      can(regex("^[a-z0-9]+((\\.|_|__|-+)[a-z0-9]+)*(/[a-z0-9]+((\\.|_|__|-+)[a-z0-9]+)*)*$", repository.name)) &&
      length(repository.name) >= 2 && length(repository.name) <= 256
    ])
    error_message = "Each ECR repository name must be 2-256 characters and match the Amazon ECR private repository naming rules."
  }

  validation {
    condition     = length(distinct([for repository in values(var.ecr_repositories) : repository.name])) == length(var.ecr_repositories)
    error_message = "Each ECR repository name must be unique."
  }

  validation {
    condition = alltrue([
      for repository in values(var.ecr_repositories) :
      repository.max_untagged_image_age >= 1 &&
      floor(repository.max_untagged_image_age) == repository.max_untagged_image_age &&
      repository.max_tagged_images >= 1 &&
      floor(repository.max_tagged_images) == repository.max_tagged_images
    ])
    error_message = "ECR retention values must be positive whole numbers."
  }
}
