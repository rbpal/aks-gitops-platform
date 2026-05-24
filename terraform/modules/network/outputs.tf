output "hub_vnet_id" {
  description = "Hub VNet ID (Azure Firewall)."
  value       = azurerm_virtual_network.hub.id
}

output "spoke_vnet_id" {
  description = "Spoke VNet ID (AKS workloads)."
  value       = azurerm_virtual_network.spoke.id
}

output "firewall_subnet_id" {
  description = "AzureFirewallSubnet ID (hub) — consumed by the firewall module."
  value       = azurerm_subnet.firewall.id
}

output "firewall_mgmt_subnet_id" {
  description = "AzureFirewallManagementSubnet ID (hub) — Basic SKU management plane."
  value       = azurerm_subnet.firewall_mgmt.id
}

output "aks_subnet_id" {
  description = "Spoke aks-nodes subnet ID — consumed by the aks module; also the LB backend pool."
  value       = azurerm_subnet.aks_nodes.id
}

output "pe_subnet_id" {
  description = "Spoke peSubnet ID — Private Endpoints for Key Vault + Service Bus."
  value       = azurerm_subnet.pe.id
}

output "node_subnet_cidr" {
  description = "aks-nodes CIDR — source for firewall egress rules."
  value       = var.node_subnet_prefix
}
