output "resource_group_name" {
  description = "The sandbox resource group everything was deployed into."
  value       = data.azurerm_resource_group.sandbox.name
}

output "location" {
  description = "Region (taken from the sandbox RG)."
  value       = data.azurerm_resource_group.sandbox.location
}

output "vnet_id" {
  description = "VNet ID."
  value       = module.network.vnet_id
}

output "aks_subnet_id" {
  description = "Node subnet ID."
  value       = module.network.aks_subnet_id
}

output "cluster_name" {
  description = "AKS cluster name (use with `az aks get-credentials`)."
  value       = module.aks.cluster_name
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL — needed for Workload Identity in Step 02 / Step 05."
  value       = module.aks.oidc_issuer_url
}

output "node_resource_group" {
  description = "Auto-created RG holding the cluster's VMSS, LB, etc."
  value       = module.aks.node_resource_group
}

# ---- Step 02: Workload Identity ----

output "key_vault_name" {
  description = "Key Vault name."
  value       = module.identity.key_vault_name
}

output "kv_reader_client_id" {
  description = "Managed identity client_id — put in the keyvault-reader SA annotation."
  value       = module.identity.kv_reader_client_id
}

output "kv_reader_sa" {
  description = "namespace/name of the ServiceAccount the federated credential expects."
  value       = "${module.identity.sa_namespace}/${module.identity.sa_name}"
}

output "signing_key_name" {
  description = "Key Vault key the payments app signs transfers with (SIGNING_KEY_NAME)."
  value       = module.identity.signing_key_name
}

# ---- Step 05: KEDA / Service Bus ----

output "servicebus_namespace_name" {
  description = "Service Bus namespace name."
  value       = module.servicebus.servicebus_namespace_name
}

output "servicebus_queue_name" {
  description = "Service Bus queue name."
  value       = module.servicebus.queue_name
}

output "servicebus_keda_connection_string" {
  description = "SAS connection string for the KEDA secret + demo sender."
  value       = module.servicebus.keda_connection_string
  sensitive   = true
}
