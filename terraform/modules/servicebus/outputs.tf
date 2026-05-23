output "servicebus_namespace_name" {
  description = "Service Bus namespace name."
  value       = azurerm_servicebus_namespace.this.name
}

output "queue_name" {
  description = "Queue name."
  value       = azurerm_servicebus_queue.demo.name
}

output "keda_connection_string" {
  description = "SAS connection string KEDA uses (also used by the demo sender). Sensitive."
  value       = azurerm_servicebus_namespace_authorization_rule.keda.primary_connection_string
  sensitive   = true
}
