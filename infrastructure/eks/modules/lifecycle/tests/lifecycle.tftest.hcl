run "create_lifecycle" {
  command = apply

  variables {
    account_id     = "123456789012"
    region         = "us-east-2"
    lifetime_hours = 4
  }

  assert {
    condition     = output.metadata.SchemaVersion == 1
    error_message = "Lifecycle metadata schema version must be 1."
  }

  assert {
    condition     = output.metadata.AccountId == "123456789012" && output.metadata.Region == "us-east-2"
    error_message = "Lifecycle metadata must bind the account and region."
  }

  assert {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", output.metadata.LabId))
    error_message = "LabId must be a canonical lowercase UUID."
  }

  assert {
    condition     = timecmp(output.metadata.ExpiresAt, timeadd(output.metadata.CreatedAt, "4h")) == 0
    error_message = "ExpiresAt must equal CreatedAt plus the selected creation lifetime."
  }
}

run "preserve_lifecycle_when_configuration_changes" {
  command = apply

  variables {
    account_id     = "123456789012"
    region         = "us-east-2"
    lifetime_hours = 12
  }

  assert {
    condition     = timecmp(output.metadata.ExpiresAt, timeadd(output.metadata.CreatedAt, "4h")) == 0
    error_message = "Existing ExpiresAt changed after lifetime configuration changed from four to twelve hours."
  }
}