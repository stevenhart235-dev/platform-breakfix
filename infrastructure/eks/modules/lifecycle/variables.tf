variable "account_id" {
  type = string
  validation {
    condition     = can(regex("^\\d{12}$", var.account_id))
    error_message = "Account ID must contain exactly 12 digits."
  }
}

variable "region" {
  type = string
  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "Region must be a valid AWS region identifier."
  }
}

variable "lifetime_hours" {
  type = number
  validation {
    condition     = var.lifetime_hours >= 1 && var.lifetime_hours <= 24 && floor(var.lifetime_hours) == var.lifetime_hours
    error_message = "EKS lifetime must be a whole number of hours from 1 through 24."
  }
}