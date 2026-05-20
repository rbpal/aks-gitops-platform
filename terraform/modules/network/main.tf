# Network module: VNet + node subnet inside an existing resource group.
# Deliberately does NOT manage the resource group — in a sandbox the RG is
# pre-created and owned by the platform, so the root passes its name in.

resource "azurerm_virtual_network" "this" {
  name                = "${var.prefix}-vnet"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = var.vnet_address_space
  tags                = var.tags
}

resource "azurerm_subnet" "aks_nodes" {
  name                 = "aks-nodes"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = var.node_subnet_prefix
}
