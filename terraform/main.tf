# Root config: looks up the sandbox's existing RG, then wires the modules.
# One `terraform apply` here brings up VNet + subnet + AKS cluster.

# The sandbox pre-creates the RG; we read it (and take its region from here, so
# location can never drift from where the sandbox actually lets you deploy).
data "azurerm_resource_group" "sandbox" {
  name = var.resource_group_name
}

# Identity of whoever is running terraform (the sandbox cloud_user). Used to
# grant yourself a Key Vault access policy so you can write/read the demo secret.
data "azurerm_client_config" "current" {}

module "network" {
  source = "./modules/network"

  prefix              = var.prefix
  resource_group_name = data.azurerm_resource_group.sandbox.name
  location            = data.azurerm_resource_group.sandbox.location
  tags                = var.tags
}

module "aks" {
  source = "./modules/aks"

  prefix              = var.prefix
  resource_group_name = data.azurerm_resource_group.sandbox.name
  location            = data.azurerm_resource_group.sandbox.location
  aks_subnet_id       = module.network.aks_subnet_id

  kubernetes_version = var.kubernetes_version
  node_count         = var.node_count
  node_vm_size       = var.node_vm_size
  tags               = var.tags
}

# Step 02 — Workload Identity target: Key Vault + user-assigned MI + federated credential.
module "identity" {
  source = "./modules/identity"

  prefix              = var.prefix
  resource_group_name = data.azurerm_resource_group.sandbox.name
  location            = data.azurerm_resource_group.sandbox.location
  tenant_id           = var.tenant_id
  admin_object_id     = data.azurerm_client_config.current.object_id
  oidc_issuer_url     = module.aks.oidc_issuer_url
  tags                = var.tags
}

# Step 05 — KEDA event source: Service Bus namespace + queue + SAS auth rule.
module "servicebus" {
  source = "./modules/servicebus"

  prefix              = var.prefix
  resource_group_name = data.azurerm_resource_group.sandbox.name
  location            = data.azurerm_resource_group.sandbox.location
  tags                = var.tags
}
