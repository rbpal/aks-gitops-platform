output "endpoint_hostname" {
  description = "Public hostname of the Front Door endpoint (xxxxx.azurefd.net) — your web app URL."
  value       = azurerm_cdn_frontdoor_endpoint.this.host_name
}

output "frontdoor_id" {
  description = "Front Door ID. Inject as the X-Azure-FDID header check at the ingress to lock the origin to THIS Front Door."
  value       = azurerm_cdn_frontdoor_profile.this.resource_guid
}
