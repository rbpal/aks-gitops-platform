output "vnet_id" {
  description = "VNet resource ID."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "VNet name."
  value       = azurerm_virtual_network.this.name
}

output "aks_subnet_id" {
  description = "Node subnet ID — consumed by the aks module."
  value       = azurerm_subnet.aks_nodes.id
}
