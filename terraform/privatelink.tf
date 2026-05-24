# Private Link for PaaS — keep PaaS traffic IN-VNET so it never egresses through
# the Azure Firewall (the spoke 0/0 UDR only catches non-VNet destinations; the
# /16 VNet route is more specific, so pod -> PE in peSubnet stays local).
#
# KEY VAULT: supported on the Standard tier -> private endpoint here.
# SERVICE BUS: Private Link is PREMIUM-only, and the sandbox's Azure Policy forces
#   the BASIC tier, so SB cannot have a PE. SB stays public and is reached over the
#   firewall (egress-network rule, port 5671). In prod (SB Premium) it would also
#   be a private endpoint and that firewall rule would be removed.

# ---- Key Vault private endpoint ----
resource "azurerm_private_dns_zone" "kv" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = data.azurerm_resource_group.sandbox.name
  tags                = var.tags
}

# Link the zone to the SPOKE VNet so in-cluster DNS resolves the KV FQDN to the
# private endpoint IP (the public name CNAMEs to *.privatelink.vaultcore.azure.net).
resource "azurerm_private_dns_zone_virtual_network_link" "kv" {
  name                  = "kv-to-spoke"
  resource_group_name   = data.azurerm_resource_group.sandbox.name
  private_dns_zone_name  = azurerm_private_dns_zone.kv.name
  virtual_network_id    = module.network.spoke_vnet_id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_endpoint" "kv" {
  name                = "${var.prefix}-kv-pe"
  resource_group_name = data.azurerm_resource_group.sandbox.name
  location            = data.azurerm_resource_group.sandbox.location
  subnet_id           = module.network.pe_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "kv"
    private_connection_resource_id = module.identity.key_vault_id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  # Auto-register the A record (KV private IP) in the zone above.
  private_dns_zone_group {
    name                 = "kv"
    private_dns_zone_ids = [azurerm_private_dns_zone.kv.id]
  }
}

output "key_vault_private_endpoint_ip" {
  description = "Key Vault private endpoint NIC IP (in peSubnet)."
  value       = azurerm_private_endpoint.kv.private_service_connection[0].private_ip_address
}
