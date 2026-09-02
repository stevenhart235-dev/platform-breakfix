module "eks_lifecycle" {
  source = "./modules/lifecycle"

  account_id     = data.aws_caller_identity.current.account_id
  region         = var.aws_region
  lifetime_hours = var.eks_lifetime_hours
}

locals {
  eks_lifecycle_metadata = module.eks_lifecycle.metadata
  eks_lifecycle_tags     = module.eks_lifecycle.tags
}