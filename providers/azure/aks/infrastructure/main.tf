locals {
  resource_group_name      = "rg-platform-breakfix-aks"
  node_resource_group_name = "rg-platform-breakfix-aks-nodes"
  vnet_name                = "vnet-platform-breakfix-aks"
  subnet_name              = "snet-aks"
  identity_name            = "id-platform-breakfix-aks"

  tags = {
    Project          = "platform-breakfix"
    PlatformBreakfix = "true"
    Provider         = "aks"
    Profile          = var.profile_name
    Purpose          = "ephemeral-lab"
    Lifecycle        = "ephemeral"
    ManagedBy        = "OpenTofu"
    CreatedAt        = time_static.lab.rfc3339
    ExpiresAt        = timeadd(time_static.lab.rfc3339, "${var.lab_ttl_hours}h")
  }
}

resource "time_static" "lab" {}

resource "azurerm_resource_group" "lab" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "lab" {
  name                = local.vnet_name
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = [var.vnet_cidr]
  tags                = local.tags
}

resource "azurerm_subnet" "aks" {
  name                 = local.subnet_name
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = [var.aks_subnet_cidr]
}

resource "azurerm_user_assigned_identity" "aks" {
  name                = local.identity_name
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

resource "azurerm_role_assignment" "aks_subnet_network_contributor" {
  scope                = azurerm_subnet.aks.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_kubernetes_cluster" "lab" {
  name                = var.cluster_name
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  dns_prefix          = var.cluster_name

  kubernetes_version                = var.kubernetes_version
  sku_tier                          = "Free"
  support_plan                      = "KubernetesOfficial"
  node_resource_group               = local.node_resource_group_name
  private_cluster_enabled           = false
  local_account_disabled            = false
  role_based_access_control_enabled = true
  oidc_issuer_enabled               = false
  workload_identity_enabled         = false
  azure_policy_enabled              = false

  default_node_pool {
    name                         = "system"
    vm_size                      = var.node_vm_size
    node_count                   = var.node_count
    auto_scaling_enabled         = false
    type                         = "VirtualMachineScaleSets"
    os_sku                       = "Ubuntu"
    os_disk_type                 = "Managed"
    os_disk_size_gb              = 64
    vnet_subnet_id               = azurerm_subnet.aks.id
    only_critical_addons_enabled = false
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = var.network_data_plane
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
  }

  storage_profile {
    disk_driver_enabled         = true
    file_driver_enabled         = false
    blob_driver_enabled         = false
    snapshot_controller_enabled = true
  }

  tags = local.tags

  depends_on = [azurerm_role_assignment.aks_subnet_network_contributor]
}
