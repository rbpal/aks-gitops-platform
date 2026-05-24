output "firewall_private_ip" {
  description = "AzFW private IP — should match the network module's firewall_private_ip (0/0 next hop)."
  value       = azurerm_firewall.this.ip_configuration[0].private_ip_address
}

output "firewall_public_ip" {
  description = "AzFW data public IP — use as the Front Door origin for this region."
  value       = azurerm_public_ip.data.ip_address
}

output "firewall_policy_id" {
  description = "Firewall policy ID."
  value       = azurerm_firewall_policy.this.id
}
