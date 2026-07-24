provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "platform-breakfix"
      ManagedBy = "OpenTofu"
      Purpose   = "Disposable training lab"
    }
  }
}
