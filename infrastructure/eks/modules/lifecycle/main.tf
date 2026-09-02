resource "random_uuid" "lab" {}

resource "time_static" "lab" {}

resource "terraform_data" "metadata" {
  input = {
    SchemaVersion = 1
    LabId         = random_uuid.lab.result
    AccountId     = var.account_id
    Region        = var.region
    CreatedAt     = time_static.lab.rfc3339
    ExpiresAt     = timeadd(time_static.lab.rfc3339, "${var.lifetime_hours}h")
  }

  lifecycle {
    ignore_changes = [input]
  }
}

resource "terraform_data" "binding_guard" {
  input = terraform_data.metadata.output

  lifecycle {
    precondition {
      condition     = var.account_id == terraform_data.metadata.output.AccountId
      error_message = "Authenticated AWS account conflicts with the existing EKS lifecycle metadata."
    }

    precondition {
      condition     = var.region == terraform_data.metadata.output.Region
      error_message = "Configured AWS region conflicts with the existing EKS lifecycle metadata."
    }
  }
}

locals {
  tags = {
    "platform-breakfix:metadata-schema" = tostring(terraform_data.binding_guard.output.SchemaVersion)
    "platform-breakfix:lab-id"          = terraform_data.binding_guard.output.LabId
    "platform-breakfix:account-id"      = terraform_data.binding_guard.output.AccountId
    "platform-breakfix:region"          = terraform_data.binding_guard.output.Region
    "platform-breakfix:created-at"      = terraform_data.binding_guard.output.CreatedAt
    "platform-breakfix:expires-at"      = terraform_data.binding_guard.output.ExpiresAt
    "platform-breakfix:provider"        = "eks"
    "platform-breakfix:lifecycle"       = "ephemeral"
  }
}