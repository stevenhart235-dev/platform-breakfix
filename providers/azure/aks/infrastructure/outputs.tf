output "provider" {
  description = "Normalized provider identifier."
  value       = "aks"
}

output "subscription_id" {
  description = "Azure subscription that owns the lab."
  value       = var.subscription_id
}

output "cluster_name" {
  description = "AKS cluster name."
  value       = azurerm_kubernetes_cluster.lab.name
}

output "cloud_location" {
  description = "Azure location containing the lab."
  value       = azurerm_resource_group.lab.location
}

output "resource_group_name" {
  description = "Primary ephemeral lab ownership boundary."
  value       = azurerm_resource_group.lab.name
}

output "node_resource_group_name" {
  description = "AKS-managed node resource group that verify-clean must check."
  value       = azurerm_kubernetes_cluster.lab.node_resource_group
}

output "kubeconfig_context" {
  description = "Deterministic context used by lifecycle tooling."
  value       = "platform-breakfix-aks"
}

output "infrastructure_root" {
  description = "Repository-relative provider infrastructure root."
  value       = "providers/azure/aks/infrastructure"
}

output "kubernetes_provider_composition" {
  description = "Repository-relative AKS Kustomize composition."
  value       = "providers/azure/aks/kubernetes"
}

output "node_vm_size" {
  description = "System node-pool VM SKU."
  value       = var.node_vm_size
}

output "node_count" {
  description = "Expected fixed system node count."
  value       = var.node_count
}
