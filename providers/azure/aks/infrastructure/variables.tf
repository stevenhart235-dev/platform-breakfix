variable "subscription_id" {
  description = "Azure subscription that owns the ephemeral AKS lab."
  type        = string
  default     = "0071dee8-974f-4f93-ad2a-0960557e1888"
}

variable "location" {
  description = "Azure region for the AKS lab."
  type        = string
  default     = "eastus2"
}

variable "cluster_name" {
  description = "AKS cluster name."
  type        = string
  default     = "platform-breakfix-aks"
}

variable "kubernetes_version" {
  description = "Exact GA AKS Kubernetes patch validated by doctor."
  type        = string
  default     = "1.35.7"
}

variable "node_vm_size" {
  description = "VM SKU for the fixed AKS system node pool."
  type        = string
  default     = "Standard_D2as_v7"
}

variable "profile_name" {
  description = "Provider-scoped AKS profile selected by lifecycle tooling."
  type        = string
  default     = "minimal"

  validation {
    condition     = contains(["minimal", "cilium", "istio"], var.profile_name)
    error_message = "profile_name must be minimal, cilium, or istio."
  }
}

variable "network_data_plane" {
  description = "AKS network data plane selected by the provider-scoped profile."
  type        = string
  default     = "azure"

  validation {
    condition     = contains(["azure", "cilium"], var.network_data_plane)
    error_message = "network_data_plane must be azure or cilium."
  }
}

variable "service_mesh_mode" {
  description = "AKS-managed service mesh mode selected by the provider-scoped profile."
  type        = string
  default     = "Disabled"

  validation {
    condition     = contains(["Disabled", "Istio"], var.service_mesh_mode)
    error_message = "service_mesh_mode must be Disabled or Istio."
  }
}

variable "istio_revision" {
  description = "Exact AKS-managed Istio revision selected by the tested profile; empty when the mesh is disabled."
  type        = string
  default     = ""

  validation {
    condition     = (var.service_mesh_mode == "Disabled" && var.istio_revision == "") || (var.service_mesh_mode == "Istio" && can(regex("^asm-[0-9]+-[0-9]+$", var.istio_revision)))
    error_message = "istio_revision must be empty when service_mesh_mode is Disabled, or an asm-X-Y revision when it is Istio."
  }
}

variable "node_count" {
  description = "Fixed node count for the Milestone 1 system pool."
  type        = number
  default     = 1
  validation {
    condition     = var.node_count == 1
    error_message = "AKS Milestone 1 uses exactly one fixed system node."
  }
}

variable "lab_ttl_hours" {
  description = "Advisory PAYG lab lifetime in hours; expires_at does not trigger automatic deletion."
  type        = number
  default     = 4

  validation {
    condition     = var.lab_ttl_hours >= 1 && var.lab_ttl_hours <= 24 && floor(var.lab_ttl_hours) == var.lab_ttl_hours
    error_message = "lab_ttl_hours must be a whole number from 1 through 24."
  }
}

variable "vnet_cidr" {
  description = "Address space for the dedicated AKS virtual network."
  type        = string
  default     = "10.20.0.0/16"
}

variable "aks_subnet_cidr" {
  description = "Address prefix for the dedicated AKS node subnet."
  type        = string
  default     = "10.20.0.0/22"
}

variable "pod_cidr" {
  description = "Azure CNI Overlay pod address space."
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  description = "Kubernetes Service address space."
  type        = string
  default     = "10.2.0.0/16"
}

variable "dns_service_ip" {
  description = "CoreDNS service IP inside the Kubernetes Service CIDR."
  type        = string
  default     = "10.2.0.10"
}
