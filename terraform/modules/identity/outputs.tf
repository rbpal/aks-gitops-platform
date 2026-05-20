output "key_vault_name" {
  description = "Key Vault name (use in `az keyvault secret show --vault-name`)."
  value       = azurerm_key_vault.this.name
}

output "key_vault_uri" {
  description = "Key Vault URI."
  value       = azurerm_key_vault.this.vault_uri
}

output "kv_reader_client_id" {
  description = "Managed identity client_id — goes in the SA annotation azure.workload.identity/client-id."
  value       = azurerm_user_assigned_identity.kv_reader.client_id
}

output "kv_reader_principal_id" {
  description = "Managed identity principal (object) ID."
  value       = azurerm_user_assigned_identity.kv_reader.principal_id
}

output "sa_namespace" {
  description = "Namespace the federated subject expects the SA in."
  value       = var.sa_namespace
}

output "sa_name" {
  description = "ServiceAccount name the federated subject expects."
  value       = var.sa_name
}

output "secret_name" {
  description = "Name of the demo secret."
  value       = azurerm_key_vault_secret.demo.name
}
