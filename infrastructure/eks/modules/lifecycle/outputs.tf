output "metadata" {
  value = terraform_data.binding_guard.output
}

output "tags" {
  value = local.tags
}