output "aws_account_id" {
  description = "AWS account ID associated with the active credentials."
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region configured for this OpenTofu root module."
  value       = var.aws_region
}

output "eks_lifecycle_metadata" {
  description = "Immutable non-secret EKS lifecycle identity persisted on AWS ownership anchors."
  value       = local.eks_lifecycle_metadata
}

output "eks_lifecycle_tags" {
  description = "Non-secret tag representation of the immutable EKS lifecycle metadata."
  value       = local.eks_lifecycle_tags
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

output "ecr_repositories" {
  description = "Created ECR repository details, keyed by the configured logical identifier."
  value = {
    for key, repository in merge(
      aws_ecr_repository.destroyable,
      aws_ecr_repository.preserved,
      ) : key => {
      name        = repository.name
      arn         = repository.arn
      uri         = repository.repository_url
      registry_id = repository.registry_id
    }
  }
}
