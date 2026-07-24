output "aws_account_id" {
  description = "AWS account ID associated with the active credentials."
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region configured for this OpenTofu root module."
  value       = var.aws_region
}

output "availability_zones" {
  description = "First three available availability zones in the configured AWS region."
  value       = slice(data.aws_availability_zones.available.names, 0, 3)
}

output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for the EKS Kubernetes API server."
  value       = module.eks.cluster_endpoint
}

output "oidc_provider" {
  description = "OpenID Connect provider URL without the URL scheme."
  value       = module.eks.oidc_provider
}

output "node_group_names" {
  description = "Names of the EKS managed node groups."
  value       = keys(module.eks.eks_managed_node_groups)
}
