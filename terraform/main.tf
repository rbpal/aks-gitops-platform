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

# Secure ingress + forced-tunnel egress: Azure Firewall (Basic) in the HUB VNet.
# Private IP lands on 10.10.0.4 (first usable in AzureFirewallSubnet) — matches
# the spoke's 0/0 route. Public IP becomes the Front Door origin.
module "firewall" {
  source = "./modules/firewall"

  prefix                  = var.prefix
  resource_group_name     = data.azurerm_resource_group.sandbox.name
  location                = data.azurerm_resource_group.sandbox.location
  firewall_subnet_id      = module.network.firewall_subnet_id
  firewall_mgmt_subnet_id = module.network.firewall_mgmt_subnet_id
  internal_lb_ip          = "10.11.1.4" # AKS node-0 IP; firewall DNATs to its ingress-nginx NodePort (sandbox denies the role assignment an internal LB needs)
  workload_source_cidrs   = module.network.node_subnet_cidr
  tags                    = var.tags
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
  outbound_type      = "userDefinedRouting" # egress through the firewall (0/0 UDR)
  tags               = var.tags

  # The firewall + its 0/0 route must exist before UDR-egress nodes can bootstrap.
  depends_on = [module.firewall]
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

# Global edge: Front Door (Standard) — free managed HTTPS cert; origin = AzFW
# public IP. This is the public entry: internet -> FD -> AzFW -> internal LB -> AKS.
module "frontdoor" {
  source = "./modules/frontdoor"

  prefix              = var.prefix
  resource_group_name = data.azurerm_resource_group.sandbox.name
  origin_host         = module.firewall.firewall_public_ip
  tags                = var.tags
}
